from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageEnhance
import os
W,H=1320,2868
F="/System/Library/Fonts/Supplemental/Arial Black.ttf"
R="/System/Library/Fonts/SFNSRounded.ttf"
Y=(255,214,64); WH=(255,255,255); OR=(255,140,40)
def bg(name, blur=6, dark=0.55):
    im=Image.open(f'bg/{name}.png').convert('RGB')
    s=max(W/im.width,H/im.height); im=im.resize((int(im.width*s)+1,int(im.height*s)+1),Image.LANCZOS)
    im=im.crop(((im.width-W)//2,(im.height-H)//2,(im.width-W)//2+W,(im.height-H)//2+H))
    if blur: im=im.filter(ImageFilter.GaussianBlur(blur))
    return ImageEnhance.Brightness(im).enhance(dark)
def text(d,y,lines):
    for t,size,col,font in lines:
        f=ImageFont.truetype(font,size); w=d.textlength(t,font=f)
        d.text(((W-w)/2,y),t,font=f,fill=col,stroke_width=size//14 if font==F else 0,stroke_fill=(0,0,0)); y+=int(size*1.22)
    return y
def phone(canvas, shot, top, scale=0.74):
    s=Image.open(f'raw/{shot}.png').convert('RGB')
    w,h=int(s.width*scale),int(s.height*scale); s=s.resize((w,h),Image.LANCZOS)
    r=int(110*scale)
    mask=Image.new('L',(w,h),0); ImageDraw.Draw(mask).rounded_rectangle((0,0,w,h),r,fill=255)
    x=(W-w)//2
    sh=Image.new('RGBA',(W,H),(0,0,0,0)); ImageDraw.Draw(sh).rounded_rectangle((x-6,top+30,x+w+6,top+h+40),r,fill=(0,0,0,170))
    canvas.paste(sh.filter(ImageFilter.GaussianBlur(40)),(0,0),sh.filter(ImageFilter.GaussianBlur(40)))
    border=Image.new('RGBA',(w+16,h+16),(0,0,0,0)); ImageDraw.Draw(border).rounded_rectangle((0,0,w+15,h+15),r+8,fill=(40,36,52,255))
    canvas.paste(border,(x-8,top-8),border)
    canvas.paste(s,(x,top),mask)
SH=[
 ("01","airpods","combo",[("PUT IN YOUR AIRPODS",84,Y,F),("Your head is the controller",58,WH,R)],True),
 ("02","arena","duck",[("DUCK THE UPPERCUT",88,Y,F),("Nod down when the banner says so",54,WH,R)],False),
 ("03","crowd","perfect",[("SLIP. COMBO. REPEAT.",84,Y,F),("Tilt left or right to slip hooks",54,WH,R)],False),
 ("04","warden","intro",[("FACE THE WARDEN",88,OR,F),("A 47-1 boss with lightning tells",54,WH,R)],False),
 ("05","win","youwin",[("COUNTER TO THE K.O.",84,Y,F),("Every slip lands a punch back",54,WH,R)],False),
 ("06","arena","menu",[("THREE FIGHTERS",92,Y,F),("Two free. Unlock the full card once.",52,WH,R)],False),
 ("07","airpods","howto",[("LEARN IN SECONDS",88,Y,F),("Built-in How to Play video",54,WH,R)],True),
 ("08","crowd","results",[("CHASE THE RECORD",88,Y,F),("Game Center leaderboards",54,WH,R)],False),
]
os.makedirs('out',exist_ok=True)
for n,b,shot,lines,ap in SH:
    c=bg(b,blur=0 if ap else 8,dark=0.9 if n=="01" else (0.75 if ap else 0.5)).convert('RGBA')
    d=ImageDraw.Draw(c)
    y=text(d,150,lines)
    if n=="01":
        phone(c,shot,1330,0.48)
    else:
        phone(c,shot,y+60,0.70)
    if ap:
        f=ImageFont.truetype(R,40); t="Works with AirPods Pro, AirPods Max, AirPods 4 & Beats Fit Pro"
        w=d.textlength(t,font=f); 
        ImageDraw.Draw(c).rounded_rectangle(((W-w)/2-30,H-150,(W+w)/2+30,H-70),40,fill=(0,0,0,170))
        ImageDraw.Draw(c).text(((W-w)/2,H-138),t,font=f,fill=WH)
    c.convert('RGB').save(f'out/{n}_{shot}.png')
print(sorted(os.listdir('out')))
