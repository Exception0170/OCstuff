from PIL import Image as PILImage
import struct
import sys
import os

class TMGConverter:
    def __init__(self):
        # OpenComputers 256-color palette (8-bit)
        self.reds = [0x00, 0x33, 0x66, 0x99, 0xCC, 0xFF]
        self.greens = [0x00, 0x24, 0x49, 0x6D, 0x92, 0xB6, 0xDB, 0xFF]
        self.blues = [0x00, 0x40, 0x80, 0xBF, 0xFF]
        self.greys = [0x0F, 0x1E, 0x2D, 0x3C, 0x4B, 0x5A, 0x69, 0x78,
                      0x87, 0x96, 0xA5, 0xB4, 0xC3, 0xD2, 0xE1, 0xF0]
        
        # 4-bit palette
        self.palette_4bit = [
            0x000000,  # black
            0xFF0000,  # red
            0x00FF00,  # darkgreen (using bright green as approximation)
            0x964B00,  # brown
            0x0000FF,  # darkblue (using blue as approximation)
            0xFF00FF,  # purple
            0x00FFFF,  # cyan
            0x404040,  # darkgray
            0x808080,  # lightgray
            0xFF8080,  # pink
            0x80FF80,  # lime
            0xFFFF00,  # yellow
            0x8080FF,  # lightblue
            0xFF0080,  # magenta
            0xFFCC00,  # gold
            0xFFFFFF   # white
        ]
    
    def collect_flags(self, depth, compRLE, compDiff, extended):
        """Pack flags into single byte: 1000=depth, 0100=RLE, 0010=Diff, 0001=extended"""
        depth_flag = 1 if depth == 8 else 0
        rle_flag = 1 if compRLE else 0
        diff_flag = 1 if compDiff else 0
        extended_flag = 1 if extended else 0
        
        flags_byte = (depth_flag << 3) | (rle_flag << 2) | (diff_flag << 1) | extended_flag
        return bytes([flags_byte])
    
    def get_flags(self, flags_byte):
        """Extract flags from byte"""
        if isinstance(flags_byte, bytes):
            flags_byte = flags_byte[0]
        
        depth = 8 if (flags_byte >> 3) & 1 else 4
        compRLE = bool((flags_byte >> 2) & 1)
        compDiff = bool((flags_byte >> 1) & 1)
        extended = bool(flags_byte & 1)
        
        return depth, compRLE, compDiff, extended
    
    def compress_rle(self, data):
        """Run-Length Encoding compression"""
        if len(data) == 0:
            return data
        
        result = bytearray()
        count = 1
        current = data[0]
        
        for i in range(1, len(data)):
            byte = data[i]
            if byte == current and count < 255:
                count += 1
            else:
                result.append(count)
                result.append(current)
                current = byte
                count = 1
        
        result.append(count)
        result.append(current)
        return bytes(result)
    
    def decompress_rle(self, data):
        """Run-Length Encoding decompression"""
        result = bytearray()
        for i in range(0, len(data), 2):
            count = data[i]
            byte = data[i + 1]
            result.extend([byte] * count)
        return bytes(result)
    
    def compress_diff(self, data):
        """Difference encoding compression"""
        if len(data) == 0:
            return data
        
        result = bytearray([data[0]])
        last = data[0]
        
        for i in range(1, len(data)):
            byte = data[i]
            diff = (byte - last) & 0xFF  # Handle wrap-around
            result.append(diff)
            last = byte
        
        return bytes(result)
    
    def decompress_diff(self, data):
        """Difference encoding decompression"""
        result = bytearray([data[0]])
        last = data[0]
        
        for i in range(1, len(data)):
            diff = data[i]
            last = (last + diff) & 0xFF
            result.append(last)
        
        return bytes(result)
    
    def auto_compress(self, data):
        """Automatically choose best compression method"""
        if len(data) < 100:
            return data, False, False  # Too small to benefit
        
        # Try different methods
        rle_data = self.compress_rle(data)
        diff_data = self.compress_diff(data)
        
        # Find best compression
        options = [
            {"data": data, "rle": False, "diff": False, "size": len(data)},
            {"data": rle_data, "rle": True, "diff": False, "size": len(rle_data)},
            {"data": diff_data, "rle": False, "diff": True, "size": len(diff_data)},
        ]
        
        # Sort by size
        options.sort(key=lambda x: x["size"])
        best = options[0]
        
        # Only use compression if it provides significant benefit
        if best["size"] < len(data) * 0.9:  # At least 10% savings
            return best["data"], best["rle"], best["diff"]
        else:
            return data, False, False
    
    def decompress_data(self, data, compRLE, compDiff):
        """Decompress data based on flags"""
        if compRLE and compDiff:
            # RLE+Diff combination (apply RLE then Diff)
            rle_decompressed = self.decompress_rle(data)
            return self.decompress_diff(rle_decompressed)
        elif compRLE:
            return self.decompress_rle(data)
        elif compDiff:
            return self.decompress_diff(data)
        else:
            return data  # No compression
    
    def nearest(self, value, lst):
        """Find nearest value in list and return its index"""
        best_idx, best_diff = 0, float('inf')
        for i, v in enumerate(lst):
            diff = abs(value - v)
            if diff < best_diff:
                best_diff = diff
                best_idx = i
        return best_idx
    
    def rgb_to_8bit_index(self, r, g, b):
        """Convert RGB to 8-bit palette index"""
        # Check if grayscale
        if r == g == b:
            if r == 0: return 0
            if r == 255: return 239
            grey_idx = self.nearest(r, self.greys)
            return 240 + grey_idx
        
        # Find nearest in RGB cube
        r_idx = self.nearest(r, self.reds)
        g_idx = self.nearest(g, self.greens)
        b_idx = self.nearest(b, self.blues)
        
        return r_idx * 40 + g_idx * 5 + b_idx
    
    def rgb_to_4bit_index(self, rgb):
        """Convert RGB to 4-bit palette index"""
        r = (rgb >> 16) & 0xFF
        g = (rgb >> 8) & 0xFF
        b = rgb & 0xFF
        
        best_idx = 0
        best_diff = float('inf')
        
        for i, palette_color in enumerate(self.palette_4bit):
            pr = (palette_color >> 16) & 0xFF
            pg = (palette_color >> 8) & 0xFF
            pb = palette_color & 0xFF
            
            diff = abs(r - pr) + abs(g - pg) + abs(b - pb)
            if diff < best_diff:
                best_diff = diff
                best_idx = i
                if diff == 0:  # Exact match
                    break
        
        return best_idx
    
    def process_image(self, image_path, output_path, depth=8, name=None, compRLE=False, compDiff=False, extended=False):
        """Convert image to .tmg format with flags"""
        try:
            # Open and convert image
            img = PILImage.open(image_path).convert('RGB')
            width, height = img.size
            
            if name is None:
                name = os.path.splitext(os.path.basename(image_path))[0]
            
            pixels = img.load()
            
            raw_data = bytearray()
            
            if depth == 4:
                # 4-bit mode: each byte contains two 4-bit colors (upper=fg, lower=bg)
                for y in range(0, height, 2):
                    for x in range(width):
                        if y + 1 < height:
                            # Get two vertical pixels
                            top_pixel = pixels[x, y]
                            bottom_pixel = pixels[x, y + 1]
                        else:
                            # Odd height - bottom pixel is black
                            top_pixel = pixels[x, y]
                            bottom_pixel = (0, 0, 0)
                        
                        # Convert to 4-bit indices
                        top_rgb = (top_pixel[0] << 16) | (top_pixel[1] << 8) | top_pixel[2]
                        bottom_rgb = (bottom_pixel[0] << 16) | (bottom_pixel[1] << 8) | bottom_pixel[2]
                        
                        top_idx = self.rgb_to_4bit_index(top_rgb)
                        bottom_idx = self.rgb_to_4bit_index(bottom_rgb)
                        
                        # Pack into one byte: upper=top, lower=bottom
                        packed = (top_idx << 4) | bottom_idx
                        raw_data.append(packed)
            
            else:  # 8-bit mode
                # 8-bit mode: each character pair represents two 8-bit colors
                for y in range(0, height, 2):
                    for x in range(width):
                        if y + 1 < height:
                            # Get two vertical pixels
                            top_pixel = pixels[x, y]
                            bottom_pixel = pixels[x, y + 1]
                        else:
                            # Odd height - bottom pixel is black
                            top_pixel = pixels[x, y]
                            bottom_pixel = (0, 0, 0)
                        
                        # Convert to 8-bit indices
                        top_idx = self.rgb_to_8bit_index(top_pixel[0], top_pixel[1], top_pixel[2])
                        bottom_idx = self.rgb_to_8bit_index(bottom_pixel[0], bottom_pixel[1], bottom_pixel[2])
                        
                        raw_data.append(top_idx)
                        raw_data.append(bottom_idx)
            
            # Apply compression if requested
            if compRLE or compDiff:
                if compRLE == "auto" or compDiff == "auto":
                    compressed_data, final_rle, final_diff = self.auto_compress(raw_data)
                else:
                    compressed_data = raw_data
                    if compRLE and compDiff:
                        compressed_data = self.compress_rle(compressed_data)
                        compressed_data = self.compress_diff(compressed_data)
                    elif compRLE:
                        compressed_data = self.compress_rle(compressed_data)
                    elif compDiff:
                        compressed_data = self.compress_diff(compressed_data)
                    final_rle = compRLE
                    final_diff = compDiff
            else:
                compressed_data = raw_data
                final_rle = False
                final_diff = False
            
            # Write .tmg file
            with open(output_path, 'wb') as f:
                # Header
                f.write(b"tmg\n")
                f.write(self.collect_flags(depth, final_rle, final_diff, extended))
                f.write("\n".encode())
                f.write(f"{name}\n".encode())
                f.write(f"{width}\n".encode())
                f.write(f"{height//2}\n".encode()) #since pixel size is 1/2 of actual y
                # Raw data
                f.write(compressed_data)
            
            print(f"Successfully converted {image_path} to {output_path}")
            print(f"Size: {width}x{height}, Depth: {depth}-bit, Name: '{name}'")
            print(f"Compression: RLE={final_rle}, DIFF={final_diff}, Extended={extended}")
            
        except Exception as e:
            print(f"Error converting {image_path}: {e}")
    
    def batch_convert(self, input_dir, output_dir, depth=8, compRLE=False, compDiff=False, extended=False):
        """Convert all images in directory"""
        if not os.path.exists(output_dir):
            os.makedirs(output_dir)
        
        supported_formats = ('.png', '.jpg', '.jpeg', '.bmp', '.gif')
        
        for filename in os.listdir(input_dir):
            if filename.lower().endswith(supported_formats):
                input_path = os.path.join(input_dir, filename)
                output_path = os.path.join(output_dir, os.path.splitext(filename)[0] + '.tmg')
                self.process_image(input_path, output_path, depth, None, compRLE, compDiff, extended)

def main():
    if len(sys.argv) < 3:
        print("Usage:")
        print("  Convert single image: python tmg_converter.py input.png output.tmg [depth] [name] [rle] [diff] [extended]")
        print("  Batch convert: python tmg_converter.py batch input_dir output_dir [depth] [rle] [diff] [extended]")
        print("")
        print("Arguments:")
        print("  depth: 4 or 8 (default: 8)")
        print("  name: image name in tmg file")
        print("  rle: 0/1/auto - Enable RLE compression (default: 0)")
        print("  diff: 0/1/auto - Enable Diff compression (default: 0)")
        return
    
    converter = TMGConverter()
    
    if sys.argv[1] == 'batch':
        input_dir = sys.argv[2]
        output_dir = sys.argv[3] if len(sys.argv) > 3 else 'converted'
        depth = int(sys.argv[4]) if len(sys.argv) > 4 else 8
        rle = sys.argv[5].lower() if len(sys.argv) > 5 else "0"
        diff = sys.argv[6].lower() if len(sys.argv) > 6 else "0"
        extended = 0
        
        # Convert string flags to proper types
        rle_flag = "auto" if rle == "auto" else (rle == "1")
        diff_flag = "auto" if diff == "auto" else (diff == "1")
        extended_flag = extended == "1"
        
        converter.batch_convert(input_dir, output_dir, depth, rle_flag, diff_flag, extended_flag)
    else:
        input_path = sys.argv[1]
        output_path = sys.argv[2]
        depth = int(sys.argv[3]) if len(sys.argv) > 3 else 8
        name = sys.argv[4] if len(sys.argv) > 4 else None
        rle = sys.argv[5].lower() if len(sys.argv) > 5 else "0"
        diff = sys.argv[6].lower() if len(sys.argv) > 6 else "0"
        extended = sys.argv[7].lower() if len(sys.argv) > 7 else "0"
        
        # Convert string flags to proper types
        rle_flag = "auto" if rle == "auto" else (rle == "1")
        diff_flag = "auto" if diff == "auto" else (diff == "1")
        extended_flag = extended == "1"
        
        converter.process_image(input_path, output_path, depth, name, rle_flag, diff_flag, extended_flag)

if __name__ == "__main__":
    main()