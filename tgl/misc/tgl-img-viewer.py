"""Small TMG viewer. Requires Pillow and, for the window, Tkinter."""
import argparse
import base64
import io
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

PALETTE4 = [0x000000, 0xFF3333, 0x336600, 0x663300, 0x333399, 0x9933CC,
            0x336699, 0x333333, 0xCCCCCC, 0xFF6699, 0x33CC33, 0xFFFF33,
            0x6699FF, 0xCC66CC, 0xFFCC33, 0xFFFFFF]
PALETTE8 = [(r << 16) | (g << 8) | b for r in (0, 51, 102, 153, 204, 255)
            for g in (0, 36, 73, 109, 146, 182, 219, 255) for b in (0, 64, 128, 191, 255)]
PALETTE8 += [gray*0x010101 for gray in range(15, 241, 15)]
CHARS = {3: '▀', 128: '█', 129: '▓', 130: '▒', 131: '▄',
         132: '▖', 133: '▗', 134: '▘', 135: '▝'}


def load_tmg(path):
    with open(path, 'rb') as file:
        if file.readline() != b'tmg\n':
            raise ValueError('Not a TMG image.')
        flag = file.read(1)
        if not flag or flag[0] > 31 or file.read(1) != b'\n':
            raise ValueError('Invalid TMG flags.')
        flags = flag[0]
        name = file.readline().decode('utf-8').rstrip('\r\n')
        width, height = float(file.readline()), float(file.readline())
        if not width.is_integer() or not height.is_integer() or width < 1 or height < 1:
            raise ValueError('Invalid image dimensions.')
        width, height = int(width), int(height)
        mask = file.read((width*height+3)//4) if flags & 16 else None
        if mask is not None and (len(mask) != (width*height+3)//4 or
                (width*height % 4 and mask[-1] >> ((width*height % 4)*2))):
            raise ValueError('Invalid transparency mask.')
        raw = file.read()
    depth, extended = (8 if flags & 8 else 4), bool(flags & 1)
    if flags & 4:
        if len(raw) % 2 or any(count == 0 for count in raw[::2]):
            raise ValueError('Invalid RLE payload.')
        limit = width*height*((2 if depth == 8 else 1)+(4 if extended else 0))
        if sum(raw[::2]) > limit:
            raise ValueError('RLE payload exceeds image dimensions.')
        raw = b''.join(bytes([value])*count for count, value in zip(raw[::2], raw[1::2]))
    if flags & 2:
        decoded, previous = bytearray(), 0
        for value in raw:
            previous = (previous+value) & 255
            decoded.append(previous)
        raw = bytes(decoded)
    if len(raw) < width*height*((2 if depth == 8 else 1)+(1 if extended else 0)):
        raise ValueError('Incomplete image data.')
    palette = PALETTE8 if depth == 8 else PALETTE4
    cw, ch = (8, 16) if extended else (1, 2)
    image = Image.new('RGBA', (width*cw, height*ch))
    font = None
    if extended:
        try:
            font = ImageFont.truetype('DejaVuSansMono.ttf', 14)
        except OSError:
            font = ImageFont.load_default()
    def color(index):
        return tuple((palette[index] >> shift) & 255 for shift in (16, 8, 0))
    pos = 0
    for cell in range(width*height):
        char = '▀'
        if extended:
            if pos >= len(raw):
                raise ValueError('Incomplete character data.')
            first = raw[pos]
            length = 2 if 0xC2 <= first <= 0xDF else 3 if 0xE0 <= first <= 0xEF else 4 if 0xF0 <= first <= 0xF4 else 1
            char = raw[pos:pos+length].decode('utf-8') if length > 1 else CHARS.get(first, chr(first) if 32 <= first < 128 else ' ')
            pos += length
        count = 2 if depth == 8 else 1
        if pos+count > len(raw):
            raise ValueError('Incomplete color data.')
        top, bottom = (raw[pos], raw[pos+1]) if depth == 8 else (raw[pos] >> 4, raw[pos] & 15)
        pos += count
        fg, bg = color(top), color(bottom)
        tile = Image.new('RGBA', (cw, ch), (*bg, 255))
        draw = ImageDraw.Draw(tile)
        if char == '▀':
            draw.rectangle((0, 0, cw-1, ch//2-1), fill=fg)
        elif char == '▄':
            draw.rectangle((0, ch//2, cw-1, ch-1), fill=fg)
        elif char == '█':
            draw.rectangle((0, 0, cw-1, ch-1), fill=fg)
        elif char in ('▖', '▗', '▘', '▝'):
            x = cw//2 if char in ('▗', '▝') else 0
            y = ch//2 if char in ('▖', '▗') else 0
            draw.rectangle((x, y, x+cw//2-1, y+ch//2-1), fill=fg)
        elif char != ' ':
            draw.text((cw/2, ch/2), char, font=font, anchor='mm', fill=fg)
        clear = (mask[cell//4] >> ((cell % 4)*2)) & 3 if mask is not None else 0
        if clear in (1, 2) and char not in ('▀', '▄', '█', ' '):
            raise ValueError('Half-cell transparency requires block or space characters.')
        if clear & 1:
            draw.rectangle((0, 0, cw-1, ch//2-1), fill=(0, 0, 0, 0))
        if clear & 2:
            draw.rectangle((0, ch//2, cw-1, ch-1), fill=(0, 0, 0, 0))
        image.paste(tile, ((cell % width)*cw, (cell//width)*ch))
    if pos != len(raw):
        raise ValueError('Unexpected trailing image data.')
    return image, dict(name=name, width=width, height=height, depth=depth,
                       extended=extended, transparent=mask is not None)


def show_window(path=None, scale=None):
    import tkinter as tk
    from tkinter import ttk, filedialog, messagebox
    try:
        root = tk.Tk()
    except tk.TclError as error:
        raise OSError(f'Cannot open a desktop window: {error}') from None
    root.title('TMG Viewer')
    root.geometry('640x480')
    toolbar = ttk.Frame(root)
    toolbar.grid(row=0, column=0, columnspan=2, sticky='ew')
    zoom = tk.StringVar(value=f'{scale or 4}x')
    choice = ttk.Combobox(toolbar, textvariable=zoom, values=('1x', '2x', '4x', '8x'), width=4, state='readonly')
    choice.pack(side='right', padx=5, pady=4)
    canvas = tk.Canvas(root, highlightthickness=0, background='#888888')
    canvas.grid(row=1, column=0, sticky='nsew')
    vertical = ttk.Scrollbar(root, orient='vertical', command=canvas.yview)
    vertical.grid(row=1, column=1, sticky='ns')
    horizontal = ttk.Scrollbar(root, orient='horizontal', command=canvas.xview)
    horizontal.grid(row=2, column=0, sticky='ew')
    canvas.configure(yscrollcommand=vertical.set, xscrollcommand=horizontal.set)
    status = tk.StringVar(value='Open a .tmg file. Ctrl+O to open; 1/2/4/8 to zoom.')
    ttk.Label(root, textvariable=status).grid(row=3, column=0, columnspan=2, sticky='w')
    root.rowconfigure(1, weight=1)
    root.columnconfigure(0, weight=1)
    state = {}

    def redraw(event=None):
        if 'image' not in state:
            return
        image = state['image']
        background = Image.new('RGBA', image.size, '#BBBBBB')
        draw = ImageDraw.Draw(background)
        for y in range(0, image.height, 4):
            for x in range(0, image.width, 4):
                if (x//4+y//4) % 2:
                    draw.rectangle((x, y, x+3, y+3), fill='#EEEEEE')
        background = Image.alpha_composite(background, image).convert('RGB')
        factor = int(zoom.get()[:-1])
        background = background.resize((image.width*factor, image.height*factor), Image.Resampling.NEAREST)
        data = io.BytesIO()
        background.save(data, format='PNG')
        state['photo'] = tk.PhotoImage(data=base64.b64encode(data.getvalue()), format='png')
        canvas.delete('all')
        canvas.create_image(0, 0, image=state['photo'], anchor='nw')
        canvas.configure(scrollregion=(0, 0, background.width, background.height))

    def open_file(filename=None):
        filename = filename or filedialog.askopenfilename(filetypes=[('TMG images', '*.tmg'), ('All files', '*')])
        if not filename:
            return
        try:
            image, info = load_tmg(filename)
        except (OSError, ValueError) as error:
            messagebox.showerror('Open image', str(error))
            return
        state['image'] = image
        zoom.set(f'{scale or (1 if info["extended"] else 4)}x')
        root.title(f'TMG Viewer - {Path(filename).name}')
        status.set(f'{info["name"]} | {info["width"]}x{info["height"]*2} pixels | {info["depth"]}-bit' +
                   (' | Extended' if info['extended'] else '') + (' | Transparency' if info['transparent'] else ''))
        canvas.xview_moveto(0)
        canvas.yview_moveto(0)
        redraw()

    ttk.Button(toolbar, text='Open...', command=open_file).pack(side='left', padx=5, pady=4)
    choice.bind('<<ComboboxSelected>>', redraw)
    root.bind('<Control-o>', lambda event: open_file())
    root.bind('<Escape>', lambda event: root.destroy())
    for factor in (1, 2, 4, 8):
        root.bind(str(factor), lambda event, n=factor: (zoom.set(f'{n}x'), redraw()))
    canvas.bind('<MouseWheel>', lambda event: canvas.yview_scroll(-1 if event.delta > 0 else 1, 'units'))
    canvas.bind('<Button-4>', lambda event: canvas.yview_scroll(-1, 'units'))
    canvas.bind('<Button-5>', lambda event: canvas.yview_scroll(1, 'units'))
    if path:
        open_file(path)
    root.mainloop()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('image', nargs='?', help='TMG file to open')
    parser.add_argument('--scale', type=int, choices=(1, 2, 4, 8), help='initial display zoom')
    parser.add_argument('--export', metavar='PNG', help='export to PNG without opening a window')
    args = parser.parse_args()
    try:
        if args.export:
            if not args.image:
                parser.error('--export requires an image file')
            image, info = load_tmg(args.image)
            image.save(args.export, format='PNG')
        else:
            show_window(args.image, args.scale)
    except (OSError, ValueError, ImportError) as error:
        parser.exit(1, f'TMG Viewer: {error}\n')


if __name__ == '__main__':
    main()
