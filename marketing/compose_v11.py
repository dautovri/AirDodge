"""1.1 App Store screenshots (iPhone 6.9", 1320x2868), 11 locales.

Inputs:  marketing/raw-1.1/<locale>/<shot>.png  (simulator captures, see
         README note in the 1.1 commit) and marketing/bg/arena*.png
         (generated pixel-art arena, no people, no headphones, no text).
Output:  marketing/screenshots-1.1/iphone-69/<locale>/NN_<shot>.png
Rules:   no prices, no headphone brands, no Apple products.
"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageEnhance
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.environ.get("AB_RAW", "/private/tmp/claude-501/airboxer-improve/store/raw")
OUT = os.path.join(HERE, "screenshots-1.1", "iphone-69")
W, H = 1320, 2868
Y = (255, 214, 64); WH = (255, 255, 255); OR = (255, 140, 40)

LATIN_HEAD = "/System/Library/Fonts/Supplemental/Arial Black.ttf"
LATIN_SUB = "/System/Library/Fonts/SFNSRounded.ttf"
JA_HEAVY = "/System/Library/Fonts/ヒラギノ角ゴシック W8.ttc"
JA_SUB = "/System/Library/Fonts/ヒラギノ角ゴシック W5.ttc"
ZH = "/System/Library/Fonts/Hiragino Sans GB.ttc"
KO = "/System/Library/Fonts/AppleSDGothicNeo.ttc"


def fonts(loc):
    if loc == "ja":
        return (JA_HEAVY, 0), (JA_SUB, 0)   # (path, ttc index): heavy, medium
    if loc == "zh-Hans":
        return (ZH, 2), (ZH, 0)
    if loc == "ko":
        return (KO, 8), (KO, 6)
    return (LATIN_HEAD, 0), (LATIN_SUB, 0)


# (shot, background, headline color)
FRAMES = [
    ("slip", "arena", Y),
    ("duck", "arena2", Y),
    ("perfect", "arena", Y),
    ("touch", "arena2", Y),
    ("menu", "arena", Y),
    ("intro", "arena2", OR),
    ("youwin", "arena", Y),
    ("howto", "arena2", Y),
]

# headline, subline per frame; footer on frame 1.
T = {
 "en-US": [("DODGE WITH YOUR HEAD", "Tilt to slip. Nod to duck."), ("DUCK THE UPPERCUT", "Nod down when the banner flashes"),
           ("STACK THE COMBO", "Every slip lands a counter-punch"), ("NO HEAD TRACKING?", "Play with touch controls"),
           ("CLIMB THE LADDER", "Beat Vitrine Bloom to face The Warden"), ("FACE THE WARDEN", "A 47-1 boss with lightning tells"),
           ("COUNTER TO THE K.O.", "Chase your record on Game Center"), ("LEARN IN SECONDS", "Animated how-to built in"),
           "Headphones that support head tracking — or touch"],
 "de-DE": [("AUSWEICHEN PER KOPF", "Neigen zum Pendeln. Nicken zum Ducken."), ("UPPERCUT ABTAUCHEN", "Nicke, wenn das Banner aufblitzt"),
           ("KOMBO AUFBAUEN", "Jedes Ausweichen setzt einen Konter"), ("KEIN HEAD-TRACKING?", "Spiel mit Touch-Steuerung"),
           ("DIE LEITER HOCH", "Besiege Vitrine Bloom für The Warden"), ("GEGEN THE WARDEN", "Ein 47-1-Boss mit Blitz-Ansagen"),
           ("KONTER ZUM K.O.", "Jag deinen Rekord in Game Center"), ("IN SEKUNDEN GELERNT", "Animierte Anleitung inklusive"),
           "Kopfhörer mit Head-Tracking – oder Touch"],
 "fr-FR": [("ESQUIVE AVEC LA TÊTE", "Penche pour esquiver. Baisse-la pour plonger."), ("PLONGE SOUS L'UPPERCUT", "Baisse la tête quand la bannière clignote"),
           ("ENCHAÎNE LES COMBOS", "Chaque esquive place une contre-attaque"), ("PAS DE SUIVI DE TÊTE ?", "Joue avec les commandes tactiles"),
           ("GRIMPE LES ÉCHELONS", "Bats Vitrine Bloom pour affronter The Warden"), ("AFFRONTE THE WARDEN", "Un boss 47-1 aux attaques éclair"),
           ("CONTRE JUSQU'AU K.-O.", "Bats ton record sur Game Center"), ("APPRIS EN SECONDES", "Tutoriel animé intégré"),
           "Écouteurs avec suivi de la tête — ou tactile"],
 "es-ES": [("ESQUIVA CON LA CABEZA", "Inclínate para esquivar. Baja para agacharte."), ("ESQUIVA EL UPPERCUT", "Baja la cabeza cuando parpadee el aviso"),
           ("ENCADENA COMBOS", "Cada esquiva conecta un contragolpe"), ("¿SIN SEGUIMIENTO?", "Juega con controles táctiles"),
           ("SUBE EN EL RANKING", "Vence a Vitrine Bloom para retar a The Warden"), ("ENFRENTA A THE WARDEN", "Un jefe 47-1 con avisos relámpago"),
           ("CONTRAGOLPE AL K.O.", "Supera tu récord en Game Center"), ("APRENDE EN SEGUNDOS", "Tutorial animado incluido"),
           "Auriculares con seguimiento de cabeza — o táctil"],
 "it":    [("SCHIVA CON LA TESTA", "Inclina per schivare. Annuisci per abbassarti."), ("EVITA IL MONTANTE", "Abbassa la testa quando lampeggia l'avviso"),
           ("CONCATENA COMBO", "Ogni schivata è un contrattacco"), ("NIENTE RILEVAMENTO?", "Gioca con i controlli touch"),
           ("SCALA LA CLASSIFICA", "Batti Vitrine Bloom per sfidare The Warden"), ("SFIDA THE WARDEN", "Un boss 47-1 con avvisi fulminei"),
           ("CONTRATTACCO AL K.O.", "Insegui il record su Game Center"), ("IMPARI IN SECONDI", "Tutorial animato incluso"),
           "Cuffie con rilevamento della testa — o touch"],
 "ja":    [("頭を動かしてかわせ", "傾けてスリップ、頷いてダッキング"), ("アッパーをくぐれ", "合図が光ったら頭を下げる"),
           ("コンボをつなげ", "かわすたびにカウンターが決まる"), ("ヘッドトラッキングなし？", "タッチ操作でも遊べる"),
           ("勝ち上がれ", "Vitrine Bloomを倒してThe Wardenへ"), ("THE WARDENに挑め", "47勝1敗、電光石火のボス"),
           ("カウンターでK.O.", "Game Centerで記録に挑戦"), ("すぐに覚えられる", "アニメーションで遊び方を解説"),
           "ヘッドトラッキング対応ヘッドフォン、またはタッチで"],
 "zh-Hans": [("用头部动作闪避", "歪头闪躲，点头下潜"), ("躲开上勾拳", "提示亮起时低头下潜"),
           ("打出连击", "每次闪避都能反击"), ("没有头部追踪？", "用触控也能玩"),
           ("一路晋级", "击败 Vitrine Bloom 挑战 The Warden"), ("挑战 THE WARDEN", "47胜1负，出拳快如闪电"),
           ("反击制胜 K.O.", "在 Game Center 刷新纪录"), ("几秒就能上手", "内置动画教程"),
           "支持头部追踪的耳机，或使用触控"],
 "ko":    [("머리로 피하라", "기울여 슬립, 숙여서 더킹"), ("어퍼컷을 피하라", "신호가 뜨면 고개를 숙이세요"),
           ("콤보를 이어가라", "피할 때마다 카운터가 터집니다"), ("헤드 트래킹이 없나요?", "터치로도 플레이"),
           ("한 단계씩 올라가라", "Vitrine Bloom을 꺾고 The Warden에 도전"), ("THE WARDEN에 도전", "47승 1패, 번개 같은 보스"),
           ("카운터로 K.O.", "Game Center에서 기록 경쟁"), ("몇 초면 익힙니다", "애니메이션 플레이 방법 내장"),
           "헤드 트래킹 지원 헤드폰 또는 터치"],
 "pt-BR": [("DESVIE COM A CABEÇA", "Incline para esquivar. Abaixe para se proteger."), ("ESCAPE DO UPPERCUT", "Abaixe a cabeça quando o aviso piscar"),
           ("MONTE O COMBO", "Cada esquiva vira um contra-ataque"), ("SEM RASTREAMENTO?", "Jogue com controles por toque"),
           ("SUBA NO RANKING", "Vença Vitrine Bloom para enfrentar The Warden"), ("ENFRENTE THE WARDEN", "Um chefão 47-1 com avisos relâmpago"),
           ("CONTRA-ATAQUE AO K.O.", "Bata seu recorde no Game Center"), ("APRENDA EM SEGUNDOS", "Tutorial animado incluso"),
           "Fones com rastreamento de cabeça — ou toque"],
 "ru":    [("УКЛОНЯЙСЯ ГОЛОВОЙ", "Наклон — уклон. Кивок — нырок."), ("НЫРНИ ПОД АППЕРКОТ", "Кивни, когда мигнёт подсказка"),
           ("СОБИРАЙ КОМБО", "Каждый уклон — контрудар"), ("НЕТ ОТСЛЕЖИВАНИЯ?", "Играй касаниями"),
           ("ПОДНИМАЙСЯ ВЫШЕ", "Победи Vitrine Bloom, чтобы выйти на The Warden"), ("БОЙ С THE WARDEN", "Босс 47-1 с молниеносными ударами"),
           ("КОНТРУДАР ДО НОКАУТА", "Бей рекорды в Game Center"), ("ОСВОИШЬ ЗА СЕКУНДЫ", "Анимированная инструкция"),
           "Наушники с отслеживанием головы — или касания"],
 "nl-NL": [("ONTWIJK MET JE HOOFD", "Kantel om te ontwijken. Knik om te bukken."), ("DUIK ONDER DE UPPERCUT", "Knik zodra de banner oplicht"),
           ("BOUW JE COMBO", "Elke ontwijking is een counter"), ("GEEN HOOFDTRACKING?", "Speel met aanraakbesturing"),
           ("KLIM DE LADDER OP", "Versla Vitrine Bloom om The Warden te treffen"), ("DAAG THE WARDEN UIT", "Een 47-1-baas met bliksemsnelle stoten"),
           ("COUNTER NAAR DE K.O.", "Jaag op je record in Game Center"), ("IN SECONDEN GELEERD", "Geanimeerde uitleg ingebouwd"),
           "Koptelefoon met hoofdtracking — of aanraken"],
}


def bg(name):
    im = Image.open(os.path.join(HERE, "bg", f"{name}.png")).convert("RGB")
    s = max(W / im.width, H / im.height)
    im = im.resize((int(im.width * s) + 1, int(im.height * s) + 1), Image.LANCZOS)
    im = im.crop(((im.width - W) // 2, (im.height - H) // 2, (im.width - W) // 2 + W, (im.height - H) // 2 + H))
    im = im.filter(ImageFilter.GaussianBlur(7))
    return ImageEnhance.Brightness(im).enhance(0.55)


def fit(d, text, spec, size, maxw):
    path, idx = spec
    while True:
        f = ImageFont.truetype(path, size, index=idx)
        if d.textlength(text, font=f) <= maxw or size < 30:
            return f
        size -= 2


def draw_center(d, y, text, font, color, stroke):
    w = d.textlength(text, font=font)
    d.text(((W - w) / 2, y), text, font=font, fill=color, stroke_width=stroke, stroke_fill=(0, 0, 0))


def phone(canvas, shot, top, scale):
    s = Image.open(shot).convert("RGB")
    w, h = int(s.width * scale), int(s.height * scale)
    s = s.resize((w, h), Image.LANCZOS)
    r = int(150 * scale)
    mask = Image.new("L", (w, h), 0); ImageDraw.Draw(mask).rounded_rectangle((0, 0, w, h), r, fill=255)
    x = (W - w) // 2
    sh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle((x - 6, top + 30, x + w + 6, top + h + 40), r, fill=(0, 0, 0, 180))
    sh = sh.filter(ImageFilter.GaussianBlur(40)); canvas.alpha_composite(sh)
    border = Image.new("RGBA", (w + 20, h + 20), (0, 0, 0, 0))
    ImageDraw.Draw(border).rounded_rectangle((0, 0, w + 19, h + 19), r + 10, fill=(44, 38, 58, 255))
    canvas.alpha_composite(border, (x - 10, top - 10))
    canvas.paste(s, (x, top), mask)


def build(loc):
    head_spec, sub_spec = fonts(loc)
    rows = T[loc]
    out = os.path.join(OUT, loc); os.makedirs(out, exist_ok=True)
    for i, (shot, b, color) in enumerate(FRAMES):
        headline, sub = rows[i]
        c = bg(b).convert("RGBA"); d = ImageDraw.Draw(c)
        hf = fit(d, headline, head_spec, 96, W - 110)
        sf = fit(d, sub, sub_spec, 58, W - 120)
        draw_center(d, 150, headline, hf, color, max(2, hf.size // 16))
        draw_center(d, 150 + int(hf.size * 1.35), sub, sf, WH, 0)
        top = 150 + int(hf.size * 1.35) + int(sf.size * 1.3) + 70
        phone(c, os.path.join(RAW, loc, f"{shot}.png"), top, 0.74)
        if i == 0:
            ff = fit(d, rows[8], sub_spec, 44, W - 160)
            w = d.textlength(rows[8], font=ff)
            d.rounded_rectangle(((W - w) / 2 - 34, H - 170, (W + w) / 2 + 34, H - 80), 45, fill=(0, 0, 0, 190))
            d.text(((W - w) / 2, H - 150), rows[8], font=ff, fill=WH)
        c.convert("RGB").save(os.path.join(out, f"{i + 1:02d}_{shot}.png"))


if __name__ == "__main__":
    for loc in (sys.argv[1:] or T):
        build(loc)
        print("built", loc)
