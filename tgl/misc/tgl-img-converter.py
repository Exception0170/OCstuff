from PIL import Image as PILImage
from PIL import ImageDraw, ImageFont
import argparse
import math
import struct
import sys
import os

class TMGConverter:
    def __init__(self, color_mode="faithful", vivid_strength=1.0):
        if color_mode not in ("legacy", "faithful", "vivid"):
            raise ValueError("color mode must be legacy, faithful or vivid")
        if not math.isfinite(vivid_strength) or not 0 <= vivid_strength <= 3:
            raise ValueError("vivid strength must be from 0 to 3")
        self.color_mode = color_mode
        self.vivid_strength = vivid_strength
        # OpenComputers 256-color palette (8-bit)
        self.reds = [0x00, 0x33, 0x66, 0x99, 0xCC, 0xFF]
        self.greens = [0x00, 0x24, 0x49, 0x6D, 0x92, 0xB6, 0xDB, 0xFF]
        self.blues = [0x00, 0x40, 0x80, 0xBF, 0xFF]
        self.greys = [0x0F, 0x1E, 0x2D, 0x3C, 0x4B, 0x5A, 0x69, 0x78,
                      0x87, 0x96, 0xA5, 0xB4, 0xC3, 0xD2, 0xE1, 0xF0]
        
        # TGL's 4-bit display palette, in tgl-img's index order.
        self.palette_4bit = [
            0x000000,  # black
            0xFF3333,  # red
            0x336600,  # darkgreen
            0x663300,  # brown
            0x333399,  # darkblue
            0x9933CC,  # purple
            0x336699,  # cyan
            0x333333,  # darkgray
            0xCCCCCC,  # lightgray
            0xFF6699,  # pink
            0x33CC33,  # lime
            0xFFFF33,  # yellow
            0x6699FF,  # lightblue
            0xCC66CC,  # magenta
            0xFFCC33,  # gold
            0xFFFFFF   # white
        ]
        self.palette_8bit = [(r << 16) | (g << 8) | b
                             for r in self.reds for g in self.greens for b in self.blues]
        self.palette_8bit.extend(grey * 0x010101 for grey in self.greys)
        self.linear = [value / 255 / 12.92 if value / 255 <= 0.04045
                       else ((value / 255 + 0.055) / 1.055) ** 2.4 for value in range(256)]
        self.lab_palettes = {}
        self.palette_chroma = {}
        self.color_cache = {}
        for depth, palette in ((4, self.palette_4bit), (8, self.palette_8bit)):
            self.lab_palettes[depth] = [self.rgb_to_oklab(color) for color in palette]
            self.palette_chroma[depth] = [math.hypot(a, b) for _, a, b in self.lab_palettes[depth]]
            self.color_cache[depth] = {color: index for index, color in enumerate(palette)}
    
    def collect_flags(self, depth, compRLE, compDiff, extended, transparency=False):
        """Pack flags: 10000=mask, 1000=depth, 0100=RLE, 0010=Diff, 0001=extended"""
        depth_flag = 1 if depth == 8 else 0
        rle_flag = 1 if compRLE else 0
        diff_flag = 1 if compDiff else 0
        extended_flag = 1 if extended else 0
        
        flags_byte = (bool(transparency) << 4) | (depth_flag << 3) | (rle_flag << 2) | (diff_flag << 1) | extended_flag
        return bytes([flags_byte])
    
    def get_flags(self, flags_byte):
        """Extract flags from byte"""
        if isinstance(flags_byte, bytes):
            flags_byte = flags_byte[0]
        
        depth = 8 if (flags_byte >> 3) & 1 else 4
        compRLE = bool((flags_byte >> 2) & 1)
        compDiff = bool((flags_byte >> 1) & 1)
        extended = bool(flags_byte & 1)
        transparency = bool(flags_byte & 16)
        
        return depth, compRLE, compDiff, extended, transparency
    
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
        if not data:
            return data
        result = bytearray([data[0]])
        last = data[0]
        
        for i in range(1, len(data)):
            diff = data[i]
            last = (last + diff) & 0xFF
            result.append(last)
        
        return bytes(result)
    
    def auto_compress(self, data):
        """Automatically choose best compression method"""
        # Try different methods
        rle_data = self.compress_rle(data)
        diff_data = self.compress_diff(data)
        rlediff_data = self.compress_rle(diff_data)
        
        # Find best compression
        options = [
            {"data": data, "rle": False, "diff": False, "size": len(data)},
            {"data": rle_data, "rle": True, "diff": False, "size": len(rle_data)},
            {"data": diff_data, "rle": False, "diff": True, "size": len(diff_data)},
            {"data": rlediff_data, "rle": True, "diff": True, "size": len(rlediff_data)},
        ]
        
        # Sort by size
        options.sort(key=lambda x: x["size"])
        best = options[0]
        
        # Flags take the same space in every mode; any payload saving is useful.
        if best["size"] < len(data):
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
    
    def rgb_to_oklab(self, rgb):
        """sRGB to Oklab, using Bjorn Ottosson's public-domain conversion matrices.
        https://bottosson.github.io/posts/oklab/
        """
        r, g, b = (self.linear[(rgb >> shift) & 255] for shift in (16, 8, 0))
        l = (0.4122214708*r + 0.5363325363*g + 0.0514459929*b) ** (1/3)
        m = (0.2119034982*r + 0.6806995451*g + 0.1073969566*b) ** (1/3)
        s = (0.0883024619*r + 0.2817188376*g + 0.6299787005*b) ** (1/3)
        return (0.2104542553*l + 0.7936177850*m - 0.0040720468*s,
                1.9779984951*l - 2.4285922050*m + 0.4505937099*s,
                0.0259040371*l + 0.7827717662*m - 0.8086757660*s)

    def nearest_color(self, rgb, depth):
        """Compare the entire palette in perceptual space, including near-gray inputs."""
        cache = self.color_cache[depth]
        if rgb in cache:
            return cache[rgb]
        if self.color_mode == "legacy":
            r, g, b = ((rgb >> shift) & 255 for shift in (16, 8, 0))
            if depth == 4:
                return min(range(16), key=lambda i: sum(abs(value-((self.palette_4bit[i] >> shift) & 255))
                           for value, shift in zip((r, g, b), (16, 8, 0))))
            if r == g == b:
                if r == 0:
                    return 0
                if r == 255:
                    return 239
                return 240 + self.nearest(r, self.greys)
            return self.nearest(r, self.reds)*40 + self.nearest(g, self.greens)*5 + self.nearest(b, self.blues)
        light, a, b = self.rgb_to_oklab(rgb)
        chroma = math.hypot(a, b)
        # Protect true neutrals, outlines and near-white highlights.
        strength = 0.0
        if self.color_mode == "vivid":
            strength = self.vivid_strength * min(1.0, max(0.0, (chroma-0.008)/0.022))
            strength *= max(0.0, min(1.0, light/0.25, (1-light)/0.06))
        best_idx = 0
        best_diff = float('inf')
        for i, (pl, pa, pb) in enumerate(self.lab_palettes[depth]):
            diff = (light-pl)**2 + (a-pa)**2 + (b-pb)**2
            if strength:
                pc = self.palette_chroma[depth][i]
                hue_loss = 0.0 if pc < 0.004 else 1-min(1.0, max(-1.0, (a*pa+b*pb)/(chroma*pc)))
                desaturation = max(0.0, chroma-pc)/max(chroma, 0.02)
                diff += strength * (0.02*hue_loss + 0.008*desaturation**2)
            if diff < best_diff:
                best_diff = diff
                best_idx = i
                if diff == 0:  # Exact match
                    break
        if len(cache) >= 8192:
            cache.clear()
        cache[rgb] = best_idx
        return best_idx

    def rgb_to_8bit_index(self, r, g, b):
        """Convert RGB to the closest of all 256 TMG colors."""
        return self.nearest_color((r << 16) | (g << 8) | b, 8)

    def rgb_to_4bit_index(self, rgb):
        """Convert RGB to the closest of the 16 TGL colors."""
        return self.nearest_color(rgb, 4)

    def quantize_pixels(self, img, depth, dither=False, alpha_threshold=128):
        """Palette indices in pixel order; optional serpentine Floyd-Steinberg in linear RGB."""
        width, height = img.size
        pixels = img.load()
        indices = bytearray(width*height)
        palette = self.palette_4bit if depth == 4 else self.palette_8bit
        if dither:
            linear_palette = [tuple(self.linear[(color >> shift) & 255] for shift in (16, 8, 0)) for color in palette]
            errors = [[0.0]*3 for _ in range(width+2)]
        for y in range(height):
            if dither:
                following = [[0.0]*3 for _ in range(width+2)]
            step = -1 if dither and y%2 else 1
            for x in range(width) if step == 1 else range(width-1, -1, -1):
                r, g, b, alpha = pixels[x, y]
                diffuse = dither and alpha >= alpha_threshold
                if diffuse:
                    adjusted = [min(1.0, max(0.0, self.linear[value]+errors[x+1][channel]))
                                for channel, value in enumerate((r, g, b))]
                    r, g, b = [round(255*(12.92*value if value <= 0.0031308
                                         else 1.055*value**(1/2.4)-0.055)) for value in adjusted]
                index = self.nearest_color((r << 16) | (g << 8) | b, depth)
                indices[y*width+x] = index
                if diffuse:
                    for channel in range(3):
                        error = adjusted[channel]-linear_palette[index][channel]
                        errors[x+1+step][channel] += error*7/16
                        following[x+1-step][channel] += error*3/16
                        following[x+1][channel] += error*5/16
                        following[x+1+step][channel] += error/16
            if dither:
                errors = following
        return indices

    def write_preview(self, img, depth, output_path, indices, dither=False, alpha_threshold=128):
        """Compare all modes with the same depth, transparency and dithering settings."""
        width, height = img.size
        scale = max(1, min(4, 320//width))
        panel_width = max(200, width*scale)
        preview = PILImage.new('RGB', (panel_width*4, height*scale+28), 'white')
        draw = ImageDraw.Draw(preview)
        font = ImageFont.load_default(size=16)
        alpha = img.getchannel('A').point(lambda value: 255 if value >= alpha_threshold else 0)
        palette = self.palette_4bit if depth == 4 else self.palette_8bit
        rgb_palette = [color >> shift & 255 for color in palette for shift in (16, 8, 0)]
        for panel, mode in enumerate((None, 'legacy', 'faithful', 'vivid')):
            if mode is None:
                image, label = img, 'Original'
            else:
                if mode == self.color_mode:
                    selected = indices
                else:
                    converter = TMGConverter(mode, self.vivid_strength)
                    selected = converter.quantize_pixels(img, depth, dither, alpha_threshold)
                image = PILImage.frombytes('P', img.size, bytes(selected))
                image.putpalette(rgb_palette + [0]*(768-len(rgb_palette)))
                image = image.convert('RGBA')
                image.putalpha(alpha)
                label = mode.title()
                if mode == 'vivid':
                    label += f" {self.vivid_strength:g}"
                if dither:
                    label += " + dither"
                if mode == self.color_mode:
                    label += " *"
            x = panel*panel_width
            draw.rectangle((x, 0, x+panel_width-1, 27), fill='#202020')
            draw.text((x+8, 4), label, font=font, fill='white')
            image = image.resize((width*scale, height*scale), PILImage.Resampling.NEAREST)
            preview.paste(image, (x, 28), image)
        preview.save(output_path)
    
    def process_image(self, image_path, output_path, depth=8, name=None, compRLE=None, compDiff=None, extended=False,
                      transparency="auto", alpha_threshold=128, dither=False, preview=False):
        """Convert image to .tmg format with flags"""
        try:
            if depth not in (4, 8):
                raise ValueError("depth must be 4 or 8")
            if transparency in ("0", "1"):
                transparency = transparency == "1"
            if transparency not in (False, True, "auto"):
                raise ValueError("transparency must be 0, 1 or auto")
            if not isinstance(alpha_threshold, int) or not 0 <= alpha_threshold <= 255:
                raise ValueError("alpha threshold must be an integer from 0 to 255")
            if compRLE is None and compDiff is None:
                compRLE, compDiff = "auto", "auto"
            else:
                compRLE = False if compRLE is None else compRLE
                compDiff = False if compDiff is None else compDiff
            # Open and convert image
            img = PILImage.open(image_path).convert('RGBA')
            width, height = img.size
            
            if name is None:
                name = os.path.splitext(os.path.basename(image_path))[0]
            if '\n' in name or '\r' in name:
                raise ValueError("image name must fit on one line")
            
            pixels = img.load()
            use_mask = (img.getchannel('A').getextrema()[0] < alpha_threshold
                        if transparency == "auto" else transparency)
            mask = bytearray((width * ((height+1)//2) + 3)//4) if use_mask else bytearray()
            if use_mask:
                for y in range(0, height, 2):
                    for x in range(width):
                        top_clear = pixels[x, y][3] < alpha_threshold
                        bottom_clear = y+1 >= height or pixels[x, y+1][3] < alpha_threshold
                        cell = (y//2)*width+x
                        mask[cell//4] |= (int(top_clear) | (int(bottom_clear) << 1)) << ((cell%4)*2)
            
            indices = self.quantize_pixels(img, depth, dither, alpha_threshold if use_mask else 0)
            raw_data = bytearray()
            for y in range(0, height, 2):
                for x in range(width):
                    if extended:
                        raw_data.append(3)  # TMG upper half-block character.
                    top = indices[y*width+x]
                    bottom = indices[(y+1)*width+x] if y+1 < height else 0
                    if depth == 4:
                        raw_data.append((top << 4) | bottom)
                    else:
                        raw_data.extend((top, bottom))

            # Apply compression if requested
            if compRLE or compDiff:
                if compRLE == "auto" or compDiff == "auto":
                    compressed_data, final_rle, final_diff = self.auto_compress(raw_data)
                else:
                    compressed_data = raw_data
                    if compRLE and compDiff:
                        compressed_data = self.compress_diff(compressed_data)
                        compressed_data = self.compress_rle(compressed_data)
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
                f.write(self.collect_flags(depth, final_rle, final_diff, extended, use_mask))
                f.write("\n".encode())
                f.write(f"{name}\n".encode())
                f.write(f"{width}\n".encode())
                f.write(f"{(height+1)//2}\n".encode()) # Two vertical pixels per cell; pad odd heights.
                # The fixed-length mask is uncompressed, with no separator before the payload.
                f.write(mask)
                f.write(compressed_data)
            if preview:
                preview_path = os.path.splitext(os.fspath(output_path))[0] + '.preview.png'
                self.write_preview(img, depth, preview_path, indices, dither, alpha_threshold if use_mask else 0)
                print(f"Preview: {preview_path} (* marks the selected mode)")
            
            print(f"Successfully converted {image_path} to {output_path}")
            print(f"Size: {width}x{height}, Depth: {depth}-bit, Name: '{name}'")
            print(f"Compression: RLE={final_rle}, DIFF={final_diff}, Extended={extended}, Transparency={use_mask}")
            print(f"Color matching: {self.color_mode}" +
                  (f" (strength {self.vivid_strength:g})" if self.color_mode == "vivid" else "") +
                  (", dithering enabled" if dither else ""))
            
        except Exception as e:
            print(f"Error converting {image_path}: {e}")
    
    def batch_convert(self, input_dir, output_dir, depth=8, compRLE=None, compDiff=None, extended=False,
                      transparency="auto", alpha_threshold=128, dither=False, preview=False):
        """Convert all images in directory"""
        if not os.path.exists(output_dir):
            os.makedirs(output_dir)
        
        supported_formats = ('.png', '.jpg', '.jpeg', '.bmp', '.gif')
        
        for filename in os.listdir(input_dir):
            if filename.lower().endswith(supported_formats):
                input_path = os.path.join(input_dir, filename)
                output_path = os.path.join(output_dir, os.path.splitext(filename)[0] + '.tmg')
                self.process_image(input_path, output_path, depth, None, compRLE, compDiff, extended,
                                   transparency, alpha_threshold, dither, preview)

def main():
    parser = argparse.ArgumentParser(description="Convert images to TMG.",
        epilog="Settings: [depth] [name] [rle] [diff] [extended] [transparency] [alpha_threshold]. Batch mode omits [name].")
    parser.add_argument("arguments", nargs="*", help="input output [settings], or batch input_dir output_dir [settings]")
    parser.add_argument("--color-mode", choices=("legacy", "faithful", "vivid"), default="faithful")
    parser.add_argument("--vivid-strength", type=float, default=1.0, help="color preservation strength from 0 to 3 (default: 1)")
    parser.add_argument("--dither", action="store_true", help="enable Floyd-Steinberg dithering")
    parser.add_argument("--preview", action="store_true", help="save a side-by-side comparison as output.preview.png")
    options = parser.parse_intermixed_args()
    argv = [sys.argv[0]] + options.arguments
    if len(argv) < 3:
        print("Usage:")
        print("  Convert single image: python tgl-img-converter.py input.png output.tmg [depth] [name] [rle] [diff] [extended] [transparency] [alpha_threshold]")
        print("  Batch convert: python tgl-img-converter.py batch input_dir output_dir [depth] [rle] [diff] [extended] [transparency] [alpha_threshold]")
        print("")
        print("Arguments:")
        print("  depth: 4 or 8 (default: 8)")
        print("  name: image name in tmg file")
        print("  rle: 0/1/auto - Set RLE compression")
        print("  diff: 0/1/auto - Set Diff compression")
        print("  Compression is automatic when both settings are omitted; explicit settings override it.")
        print("  extended: 0/1 - Store a half-block character with each cell (default: 0)")
        print("  transparency: 0/1/auto - Write a TMG 1.7 mask (default: auto, only when needed)")
        print("  alpha_threshold: 0-255 - Alpha below this value is transparent (default: 128)")
        print("  --color-mode legacy|faithful|vivid: choose color matching (default: faithful)")
        print("  --vivid-strength 0-3: Vivid strength; 0 behaves like Faithful (default: 1)")
        print("  --dither: enable Floyd-Steinberg dithering")
        print("  --preview: save Original/Legacy/Faithful/Vivid comparison as output.preview.png")
        return
    
    try:
        converter = TMGConverter(options.color_mode, options.vivid_strength)
    except ValueError as error:
        parser.error(str(error))
    
    if argv[1] == 'batch':
        input_dir = argv[2]
        output_dir = argv[3] if len(argv) > 3 else 'converted'
        depth = int(argv[4]) if len(argv) > 4 else 8
        rle = argv[5].lower() if len(argv) > 5 else None
        diff = argv[6].lower() if len(argv) > 6 else None
        extended = argv[7].lower() if len(argv) > 7 else "0"
        transparency = argv[8].lower() if len(argv) > 8 else "auto"
        alpha_threshold = int(argv[9]) if len(argv) > 9 else 128
        
        # Convert string flags to proper types
        rle_flag = None if rle is None else "auto" if rle == "auto" else (rle == "1")
        diff_flag = None if diff is None else "auto" if diff == "auto" else (diff == "1")
        extended_flag = extended == "1"
        
        converter.batch_convert(input_dir, output_dir, depth, rle_flag, diff_flag, extended_flag,
                                transparency, alpha_threshold, options.dither, options.preview)
    else:
        input_path = argv[1]
        output_path = argv[2]
        depth = int(argv[3]) if len(argv) > 3 else 8
        name = argv[4] if len(argv) > 4 else None
        rle = argv[5].lower() if len(argv) > 5 else None
        diff = argv[6].lower() if len(argv) > 6 else None
        extended = argv[7].lower() if len(argv) > 7 else "0"
        transparency = argv[8].lower() if len(argv) > 8 else "auto"
        alpha_threshold = int(argv[9]) if len(argv) > 9 else 128
        
        # Convert string flags to proper types
        rle_flag = None if rle is None else "auto" if rle == "auto" else (rle == "1")
        diff_flag = None if diff is None else "auto" if diff == "auto" else (diff == "1")
        extended_flag = extended == "1"
        
        converter.process_image(input_path, output_path, depth, name, rle_flag, diff_flag, extended_flag,
                                transparency, alpha_threshold, options.dither, options.preview)

if __name__ == "__main__":
    main()
