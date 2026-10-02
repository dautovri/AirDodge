from PIL import Image, ImageDraw, ImageFont
import subprocess
F="/System/Library/Fonts/Supplemental/Arial Black.ttf"
def cap(name, lines, y0, bg=None):
    im=Image.new('RGBA',(1080,1920),bg or (0,0,0,0)); d=ImageDraw.Draw(im); y=y0
    for text,size,col in lines:
        f=ImageFont.truetype(F,size); w=d.textlength(text,font=f)
        d.text(((1080-w)/2,y),text,font=f,fill=col,stroke_width=max(4,size//12),stroke_fill=(0,0,0,255)); y+=int(size*1.3)
    im.save(f'cap/{name}.png')
Y=(255,214,64,255); W=(255,255,255,255); O=(255,140,40,255)
cap('c0',[("AIRBOXER",130,Y)],200)
cap('c1',[("YOUR HEAD",100,W),("IS THE CONTROLLER",70,Y)],200)
cap('c2',[("TILT TO SLIP",84,W),("DUCK THE UPPERCUT",70,Y)],1500)
cap('c3',[("BEAT THE WARDEN",88,O)],200)
cap('c5',[("AIRBOXER",140,Y),("Free on the App Store",58,W),("Works with AirPods Pro, AirPods Max,",36,(255,255,255,190)),("AirPods (3rd gen), AirPods 4 & Beats Fit Pro",36,(255,255,255,190))],680,(15,13,23,255))
cap('ca',[("PUT IN",90,W),("YOUR AIRPODS",100,Y)],200)
fc=("[11:v]scale=1080:1920,setsar=1,fps=30[ba];[ba][12:v]overlay[va];"
    "[0:v]scale=1200:2134,crop=1080:1920:60:200,setsar=1,fps=30[b0];[b0][6:v]overlay[v0];"
    "[1:v]scale=1080:1920,setsar=1,fps=30[b1];[b1][7:v]overlay[v1];"
    "[2:v]scale=1080:-2,crop=1080:1920:0:60,setsar=1,fps=30[b2];[b2][8:v]overlay[v2];"
    "[3:v]scale=1080:1920,setsar=1,fps=30[b3];[b3][9:v]overlay[v3];"
    "[4:v]scale=1080:1920,setsar=1,fps=30[v4];"
    "[10:v]scale=1080:1920,setsar=1,fps=30[v5];"
    "[va][v0][v1][v2][v3][v4][v5]concat=n=7:v=1:a=0,format=yuv420p[v];"
    "[5:a]aloop=loop=1:size=2000000,atrim=0:29,asetpts=PTS-STARTPTS,afade=t=in:d=0.3,afade=t=out:st=27.3:d=1.7[a]")
cmd=["ffmpeg","-v","error","-y",
 "-t","3.5","-i","veo/trailer_arena.mp4",
 "-t","3","-i","veo/trailer_player.mp4",
 "-ss","7","-t","6.5","-i","fight_vitrine.mp4",
 "-t","4.5","-i","veo/trailer_warden.mp4",
 "-ss","4.5","-t","3","-i","veo/trailer_player.mp4",
 "-i","lyria/out/menu_loop.caf",
 "-loop","1","-t","3.5","-i","cap/c0.png",
 "-loop","1","-t","3","-i","cap/c1.png",
 "-loop","1","-t","6.5","-i","cap/c2.png",
 "-loop","1","-t","4.5","-i","cap/c3.png",
 "-loop","1","-t","3.5","-framerate","30","-i","cap/c5.png",
 "-t","5","-i","veo/airpods_in_tall.mp4",
 "-loop","1","-t","5","-i","cap/ca.png",
 "-filter_complex",fc,"-map","[v]","-map","[a]","-c:v","libx264","-crf","20","-preset","slow","-c:a","aac","-b:a","160k","-movflags","+faststart","-shortest","airboxer_trailer.mp4"]
# overlays need shortest per segment
fc2=fc.replace("overlay[","overlay=shortest=1[")
cmd[cmd.index(fc)]=fc2
subprocess.run(cmd,check=True)
