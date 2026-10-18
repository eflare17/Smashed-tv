from PIL import Image, ImageDraw, ImageFont
import random
SP='./'
# leaf templates. K outline, D dark, G mid, H vein/highlight, S stalk, T tip colour (purple/blue strains)
BROAD=[".....KKK.....","....KGGGK....","....KGHGK....",".KK.KGHGK.KK.","KGGKKGHGKKGGK","KTGGKGHGKGGTK",".KTGHKHKHGTK.","KK.KGHHHGK.KK","KGGKKGHGKKGGK",".KTGGGHGGGTK.","..KKKKHKKKK..",".....KSK....."]
THIN=["......K......",".....KHK.....",".....KHK.....",".K...KHK...K.","KTK..KHK..KTK",".KHK.KHK.KHK.","..KHKKHKKHK..","K..KHKHKHK..K","TKK.KHHHK.KKT",".KHHKKHKKHHK.","..KKKKHKKKK..",".....KSK....."]
MID=["......K......",".....KGK.....",".....KHK.....",".KK..KHK..KK.","KTGK.KHK.KGTK",".KHGKKHKKGHK.","..KHGKHKGHK..","KK.KHGHGHK.KK","KTGKKHHHKKGTK",".KHHGGHGGHHK.","..KKKKHKKKK..",".....KSK....."]
SMALL={'broad':["...KKK...","..KGHGK..","K.KGHGK.K","GKKGHGKKG","KTGKHKGTK",".KHGHGHK.","..KKHKK..","....S...."],
       'thin':["....K....","...KHK...","K..KHK..K","TK.KHK.KT","KHKKHKKHK",".KHKHKHK.","..KKHKK..","....S...."]}
SMALL['mid']=["....K....","...KHK...","K..KHK..K","TK.KHK.KT","KHKKHKKHK",".KHGHGHK.","..KKHKK..","....S...."]
def grid(r): return [list(x) for x in r]
def tilt(g,dirn):
    h=len(g); w=len(g[0]); out=[['.']*(w+h//2) for _ in range(h)]
    for y in range(h):
        off=(h-1-y)//2 if dirn>0 else y//2
        for x in range(w):
            if g[y][x]!='.': out[y][x+off]=g[y][x]
    return out
def plant(st, stage):
    P=st['pal']; W,H=44,64; GY=H-4; im=Image.new('RGBA',(W,H),(0,0,0,0))
    def put(x,y,c):
        if 0<=x<W and 0<=y<H: im.putpixel((x,y),P[c]+(255,))
    def stamp(g,x0,y0):
        for y,row in enumerate(g):
            for x,c in enumerate(row):
                if c!='.': put(x0+x,y0+y,c)
    def line(x0,y0,x1,y1):
        n=max(abs(x1-x0),abs(y1-y0),1)
        for i in range(n+1): put(round(x0+(x1-x0)*i/n),round(y0+(y1-y0)*i/n),'S')
    cx=W//2-1; kind=st['leaf']; B=grid({'broad':BROAD,'thin':THIN,'mid':MID}[kind]); S=grid(SMALL[kind])
    tall={'broad':34,'mid':40,'thin':48}[kind]
    def stemup(y0): 
        for y in range(y0,GY+1): put(cx,y,'S'); put(cx+1,y,'D')
    if stage==0:
        stemup(GY-6); stamp(grid(["KK...KK","KGK.KGK",".KKSKK."]),cx-3,GY-8); stamp(S,cx-4,GY-15); return im
    if stage==1:
        stemup(GY-16); line(cx,GY-6,cx-5,GY-9); line(cx+1,GY-6,cx+6,GY-9)
        stamp(tilt(S,-1),cx-11,GY-12); stamp(tilt(S,1),cx+2,GY-12); stamp(S,cx-4,GY-23); return im
    top=GY-tall; stemup(top+8)
    nodes=[GY-8, GY-8-(tall-10)//3, GY-8-2*(tall-10)//3]
    for i,ny in enumerate(nodes):
        big=(i==0) or (kind=='broad' and i==1)
        g=B if big else S; sp=9 if big else 6
        line(cx,ny+2,cx-sp,ny-2); line(cx+1,ny+2,cx+sp+1,ny-2)
        stamp(tilt(g,-1),cx-(19 if big else 13),ny-(10 if big else 6)); stamp(tilt(g,1),cx+2,ny-(10 if big else 6))
    stamp(B,cx-6,top)
    if stage==3:
        random.seed(st['name'])
        def cola(x0,y0,w,h):
            for y in range(h):
                ww=max(1,round(w*(0.55+0.45*(1-abs(y-h*0.45)/(h*0.6)))))
                for x in range(ww):
                    X=x0+x-ww//2; c='b' if x in (0,ww-1) else ('B' if (x+y)%3 else 'w')
                    put(X,y0+y,c)
            for _ in range(w*h//5): put(x0+random.randint(-w//2,w//2-1), y0+random.randint(0,h-1),'o')     # hairs
            for _ in range(st.get('frost',0)*w*h//10): put(x0+random.randint(-w//2,w//2-1), y0+random.randint(0,h-1),'w')
        cola(cx+1,top-6,7 if kind!='thin' else 5,12 if kind!='broad' else 10)
        for i,ny in enumerate(nodes):
            for side in (-1,1): cola(cx+1+side*(8 if i==0 else 6), ny-4, 5 if kind=='broad' else 4, 5)
    return im
BASE={'K':(18,32,16),'S':(86,118,48),'o':(226,138,62),'w':(236,240,214)}
def pal(D,G,H,T,B,b,o=None):
    p=dict(BASE); p.update({'D':D,'G':G,'H':H,'T':T,'B':B,'b':b});
    if o: p['o']=o
    return p
STRAINS=[
 {'name':'Northern Lights','tier':'Common','type':'Indica','leaf':'broad','frost':1,'effect':'Small health boost','pal':pal((34,78,36),(52,112,46),(96,160,70),(52,112,46),(168,190,110),(110,132,66))},
 {'name':'Sour Diesel','tier':'Uncommon','type':'Sativa','leaf':'thin','frost':1,'effect':'Run and fire faster','pal':pal((58,110,34),(96,156,50),(160,212,84),(130,190,60),(206,214,120),(150,160,76),(236,150,60))},
 {'name':'Granddaddy Purple','tier':'Uncommon','type':'Indica','leaf':'broad','frost':1,'effect':'Slower, take less damage','pal':pal((40,58,44),(60,96,56),(110,148,86),(112,60,130),(150,96,180),(96,58,120),(232,160,90))},
 {'name':'Blue Dream','tier':'Rare','type':'Hybrid','leaf':'mid','frost':2,'effect':'Slow-mo: enemies slow down','pal':pal((32,82,74),(50,122,104),(110,178,150),(70,120,160),(170,206,210),(104,140,150))},
 {'name':'Acapulco Gold','tier':'Rare','type':'Sativa','leaf':'thin','frost':1,'effect':'Double cash from kills','pal':pal((70,96,30),(118,146,44),(184,198,80),(196,160,50),(226,190,90),(170,130,50),(214,110,40))},
 {'name':'White Widow','tier':'Legendary','type':'Hybrid','leaf':'mid','frost':4,'effect':'Big damage boost + trippy','pal':pal((40,84,52),(66,124,72),(134,182,124),(150,180,150),(232,238,226),(178,190,176))},
]
if __name__=='__main__':
    F=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',13); f=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',11)
    Z=4; W,H=44,64; cell=W*Z+16
    out=Image.new('RGB',(cell*len(STRAINS)+16,H*Z+96),(28,30,38)); d=ImageDraw.Draw(out)
    TC={'Common':(200,200,200),'Uncommon':(110,220,110),'Rare':(110,170,255),'Legendary':(255,190,70)}
    for i,st in enumerate(STRAINS):
        im=plant(st,3); bg=Image.new('RGBA',im.size,(98,68,48,255)); bg.alpha_composite(im)
        x=16+i*cell; out.paste(bg.resize((W*Z,H*Z),Image.NEAREST),(x,12))
        cxx=x+W*Z//2
        d.text((cxx,H*Z+28),st['name'],font=F,fill=(255,255,255),anchor='mm')
        d.text((cxx,H*Z+46),st['type']+' · '+st['tier'],font=f,fill=TC[st['tier']],anchor='mm')
        d.text((cxx,H*Z+64),st['effect'],font=f,fill=(210,210,220),anchor='mm')
    out.save(SP + 'strains-preview.png')
    # all stages of each, small, to check growth reads
    g=Image.new('RGBA',(W*4*2+20,H*len(STRAINS)*2),(98,68,48,255))
    for r,st in enumerate(STRAINS):
        for s in range(4): g.alpha_composite(plant(st,s).resize((W*2,H*2),Image.NEAREST),(s*W*2,r*H*2))
    g.save(SP+'strains_growth.png')
