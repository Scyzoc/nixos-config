{ pkgs, ... }:

{
  # --- Theme Rofi pour le selecteur d'emojis ---
  xdg.configFile."rofi/emoji.rasi".text = ''
    configuration {
        show-icons: false;
        font: "Inter 12";
        me-select-entry: "";
        me-accept-entry: "MousePrimary";
        pango-markup: true;
    }
    * {
        background-color: transparent;
        text-color: #ffffff;
    }
    window {
        width: 600px;
        border: 2px;
        border-color: rgba(255, 255, 255, 0.2);
        border-radius: 15px;
        background-color: rgba(0, 0, 0, 0.25);
        padding: 10px;
    }
    mainbox { spacing: 10px; }
    inputbar {
        padding: 8px 12px;
        margin: 0px 0px 4px 0px;
        background-color: rgba(255, 255, 255, 0.05);
        border: 1px;
        border-color: rgba(255, 255, 255, 0.1);
        border-radius: 10px;
        children: [prompt, textbox-prompt-sep, entry];
    }
    prompt {
        color: rgba(255, 255, 255, 0.7);
        font: "JetBrainsMono Nerd Font 14";
        vertical-align: 0.5;
        padding: 0px 4px 0px 0px;
    }
    textbox-prompt-sep {
        str: "│";
        expand: false;
        color: rgba(255, 255, 255, 0.2);
        vertical-align: 0.5;
        padding: 0px 8px;
    }
    entry {
        color: #ffffff;
        placeholder: "Rechercher un emoji...";
        placeholder-color: rgba(255, 255, 255, 0.3);
        vertical-align: 0.5;
    }
    listview {
        columns: 6;
        lines: 10;
        spacing: 8px;
        scrollbar: false;
        padding: 10px;
    }
    element {
        padding: 8px;
        border-radius: 10px;
        vertical-align: 0.5;
        horizontal-align: 0.5;
    }
    element-text {
        background-color: transparent;
        text-color: #ffffff;
        font: "JetBrainsMono Nerd Font 22";
        horizontal-align: 0.5;
    }
    element selected {
        background-color: rgba(255, 255, 255, 0.1);
        border: 2px;
        border-color: #ffffff;
    }
  '';

  # Fichier de donnees des emojis
  # ==========================================================================
  xdg.configFile."rofi/emoji-data".text = ''
😀 grinning face
😃 grinning face with big eyes
😄 grinning face with smiling eyes
😁 beaming face with smiling eyes
😆 grinning squinting face
😅 grinning face with sweat
🤣 rolling on the floor laughing
😂 face with tears of joy
🙂 slightly smiling face
🙃 upside-down face
😉 winking face
😊 smiling face with smiling eyes
😇 smiling face with halo
🥰 smiling face with hearts
😍 smiling face with heart-eyes
🤩 star-struck
😘 face blowing a kiss
😗 kissing face
😚 kissing face with closed eyes
😙 kissing face with smiling eyes
😋 face savoring food
😛 face with tongue
😜 winking face with tongue
🤪 zany face
😝 squinting face with tongue
🤑 money-mouth face
🤗 hugging face
🤭 face with hand over mouth
🤫 shushing face
🤔 thinking face
🫡 saluting face
🤐 zipper-mouth face
🤨 face with raised eyebrow
😐 neutral face
😑 expressionless face
😶 face without mouth
🫥 dotted line face
😏 smirking face
😒 unamused face
🙄 face with rolling eyes
😬 grimacing face
🤥 lying face
😌 relieved face
😔 pensive face
😪 sleepy face
🤤 drooling face
😴 sleeping face
😷 face with medical mask
🤒 face with thermometer
🤕 face with head-bandage
🤢 nauseated face
🤮 face vomiting
🥵 hot face
🥶 cold face
🥴 woozy face
😵 knocked-out face
🤯 exploding head
🤠 cowboy hat face
🥳 partying face
🥸 disguised face
😎 smiling face with sunglasses
🤓 nerd face
🧐 face with monocle
😕 confused face
🫤 face with diagonal mouth
😟 worried face
🙁 slightly frowning face
☹️ frowning face
😮 face with open mouth
😯 hushed face
😲 astonished face
😳 flushed face
🥺 pleading face
🥹 face holding back tears
😦 frowning face with open mouth
😧 anguished face
😨 fearful face
😰 anxious face with sweat
😥 sad but relieved face
😢 crying face
😭 loudly crying face
😱 face screaming in fear
😖 confounded face
😣 persevering face
😞 disappointed face
😓 downcast face with sweat
😩 weary face
😫 tired face
🥱 yawning face
🥲 smiling face with tear
🫠 melting face
🫢 face with open eyes and hand over mouth
🫣 face with peeking eye
🫦 biting lip
🫨 shaking face
😤 face with steam from nose
😡 pouting face
😠 angry face
🤬 face with symbols on mouth
😈 smiling face with horns
👿 angry face with horns
💀 skull
☠️ skull and crossbones
💩 pile of poo
🤡 clown face
👹 ogre
👺 goblin
👻 ghost
👽 alien
👾 alien monster
🤖 robot
😺 grinning cat
😸 grinning cat with smiling eyes
😹 cat with tears of joy
😻 smiling cat with heart-eyes
😼 cat with wry smile
😽 kissing cat
🙀 weary cat
😿 crying cat
😾 pouting cat
🙈 see-no-evil monkey
🙉 hear-no-evil monkey
🙊 speak-no-evil monkey
💌 love letter
💘 heart with arrow
💝 heart with ribbon
💖 sparkling heart
💗 growing heart
💓 beating heart
💞 revolving hearts
💕 two hearts
💟 heart decoration
❣️ heart exclamation
💔 broken heart
❤️ red heart
🧡 orange heart
💛 yellow heart
💚 green heart
💙 blue heart
💜 purple heart
🤎 brown heart
🖤 black heart
🤍 white heart
🩷 pink heart
🩵 light blue heart
🩶 grey heart
❤️‍🔥 heart on fire
❤️‍🩹 mending heart
💯 hundred points
💢 anger symbol
💥 collision
💫 dizzy
💦 sweat droplets
💨 dashing away
👋 waving hand
🤚 raised back of hand
✋ raised hand
🖖 vulcan salute
👌 ok hand
🤌 pinched fingers
🤏 pinching hand
✌️ victory hand
🤞 crossed fingers
🤟 love-you gesture
🤘 sign of the horns
🤙 call me hand
👈 backhand index pointing left
👉 backhand index pointing right
👆 backhand index pointing up
🖕 middle finger
👇 backhand index pointing down
☝️ index pointing up
👍 thumbs up
👎 thumbs down
✊ raised fist
👊 oncoming fist
🤛 left-facing fist
🤜 right-facing fist
👏 clapping hands
🙌 raising hands
🫶 heart hands
🫱 rightwards hand
🫲 leftwards hand
🫳 palm down hand
🫴 palm up hand
🫵 index pointing at viewer
🫷 leftwards pushing hand
🫸 rightwards pushing hand
🫰 hand with index finger and thumb crossed
👐 open hands
🤲 palms up together
🤝 handshake
🙏 folded hands
✍️ writing hand
💅 nail polish
🤳 selfie
💪 flexed biceps
🦾 mechanical arm
🦿 mechanical leg
🦵 leg
🦶 foot
👂 ear
👃 nose
🧠 brain
🫀 anatomical heart
🫁 lungs
🦷 tooth
🦴 bone
👀 eyes
👁️ eye
👅 tongue
👄 mouth
👶 baby
🧒 child
👦 boy
👧 girl
🧑 person
👨 man
🧔 person beard
👩 woman
🧓 older person
👴 old man
👵 old woman
🙍 person frowning
🙎 person pouting
🙅 person gesturing no
🙆 person gesturing ok
💁 person tipping hand
🙋 person raising hand
🙇 person bowing
🤦 person facepalming
🤷 person shrugging
👮 police officer
🕵️ detective
💂 guard
🥷 ninja
👷 construction worker
🤴 prince
👸 princess
👳 person wearing turban
👲 person with skullcap
🧕 woman with headscarf
🤵 person in tuxedo
👰 person with veil
🤰 pregnant woman
🤱 breast-feeding
👼 baby angel
🎅 santa claus
🤶 mrs claus
🦸 superhero
🦹 supervillain
🧙 mage
🧚 fairy
🧛 vampire
🧜 merperson
🧝 elf
🧞 genie
🧟 zombie
💆 person getting massage
💇 person getting haircut
🚶 person walking
🧍 person standing
🧎 person kneeling
🏃 person running
💃 woman dancing
🕺 man dancing
👯 people with bunny ears
🧖 person in steamy room
🧗 person climbing
🤺 person fencing
🏇 horse racing
⛷️ skier
🏂 snowboarder
🏌️ person golfing
🏄 person surfing
🚣 person rowing boat
🏊 person swimming
⛹️ person bouncing ball
🏋️ person lifting weights
🚴 person biking
🚵 person mountain biking
🤸 person cartwheeling
🤼 people wrestling
🤽 person playing water polo
🤾 person playing handball
🤹 person juggling
🧘 person in lotus position
🛀 person taking bath
🛌 person in bed
💏 kiss
💑 couple with heart
👪 family
🗣️ speaking head
👤 bust in silhouette
👥 busts in silhouette
👣 footprints
🐵 monkey face
🐒 monkey
🦍 gorilla
🦧 orangutan
🐶 dog face
🐕 dog
🐩 poodle
🐺 wolf
🦊 fox
🐱 cat face
🐈 cat
🦁 lion
🐯 tiger face
🐅 tiger
🐆 leopard
🐴 horse face
🐎 horse
🦄 unicorn
🦓 zebra
🦌 deer
🐮 cow face
🐂 ox
🐃 water buffalo
🐄 cow
🐷 pig face
🐖 pig
🐗 boar
🐽 pig nose
🐏 ram
🐑 ewe
🐐 goat
🐪 camel
🐫 two-hump camel
🦙 llama
🦒 giraffe
🦘 kangaroo
🦬 bison
🦣 mammoth
🦛 hippopotamus
🐘 elephant
🦏 rhinoceros
🐭 mouse face
🐁 mouse
🐀 rat
🐹 hamster
🐰 rabbit face
🐇 rabbit
🐿️ chipmunk
🦔 hedgehog
🦥 sloth
🦦 otter
🦨 skunk
🦡 badger
🦝 raccoon
🦇 bat
🐻 bear
🐨 koala
🐼 panda
🐾 paw prints
🦃 turkey
🐔 chicken
🐓 rooster
🐣 hatching chick
🐤 baby chick
🐥 front-facing baby chick
🐦 bird
🐧 penguin
🕊️ dove
🦅 eagle
🦆 duck
🦢 swan
🦉 owl
🦚 peacock
🦜 parrot
🦤 dodo
🪶 feather
🪿 goose
🐦‍⬛ black bird
🐸 frog
🐊 crocodile
🐢 turtle
🦎 lizard
🐍 snake
🐲 dragon face
🐉 dragon
🐳 spouting whale
🐋 whale
🐬 dolphin
🐟 fish
🐠 tropical fish
🐡 blowfish
🦈 shark
🦭 seal
🐙 octopus
🐚 spiral shell
🪸 coral
🐌 snail
🦋 butterfly
🐛 bug
🐜 ant
🐝 honeybee
🐞 lady beetle
🕷️ spider
🦂 scorpion
🦗 cricket
🦟 mosquito
🦠 microbe
🪲 beetle
🪳 cockroach
🪰 fly
🪱 worm
💐 bouquet
🌸 cherry blossom
💮 white flower
🏵️ rosette
🌹 rose
🥀 wilted flower
🌺 hibiscus
🌻 sunflower
🌼 blossom
🌷 tulip
🪷 lotus
🪻 hyacinth
🌱 seedling
🌲 evergreen tree
🌳 deciduous tree
🌴 palm tree
🌵 cactus
🌾 sheaf of rice
🌿 herb
☘️ shamrock
🍀 four leaf clover
🍁 maple leaf
🍂 fallen leaf
🍃 leaf fluttering in wind
🍇 grapes
🍈 melon
🍉 watermelon
🍊 tangerine
🍋 lemon
🍌 banana
🍍 pineapple
🥭 mango
🍎 red apple
🍏 green apple
🍐 pear
🍑 peach
🍒 cherries
🍓 strawberry
🥝 kiwi fruit
🍅 tomato
🥥 coconut
🥑 avocado
🍆 eggplant
🥔 potato
🥕 carrot
🌽 ear of corn
🌶️ hot pepper
🥒 cucumber
🥬 leafy green
🥦 broccoli
🧄 garlic
🧅 onion
🥜 peanuts
🌰 chestnut
🍞 bread
🥐 croissant
🥖 baguette bread
🥨 pretzel
🥯 bagel
🥞 pancakes
🧀 cheese wedge
🍖 meat on bone
🍗 poultry leg
🥩 cut of meat
🥓 bacon
🍔 hamburger
🍟 french fries
🍕 pizza
🌭 hot dog
🥪 sandwich
🌮 taco
🌯 burrito
🥙 stuffed flatbread
🥚 egg
🍳 cooking
🧆 falafel
🥘 shallow pan of food
🍲 pot of food
🥣 bowl with spoon
🥗 green salad
🍿 popcorn
🧈 butter
🧂 salt
🥫 canned food
🍱 bento box
🍘 rice cracker
🍙 rice ball
🍚 cooked rice
🍛 curry rice
🍜 steaming bowl
🍝 spaghetti
🍠 roasted sweet potato
🍢 oden
🍣 sushi
🍤 fried shrimp
🍥 fish cake with swirl
🥮 moon cake
🍡 dango
🥟 dumpling
🥠 fortune cookie
🥡 takeout box
🦀 crab
🦞 lobster
🦐 shrimp
🦑 squid
🦪 oyster
🍦 soft ice cream
🍧 shaved ice
🍨 ice cream
🍩 doughnut
🍪 cookie
🎂 birthday cake
🍰 shortcake
🧁 cupcake
🥧 pie
🍫 chocolate bar
🍬 candy
🍭 lollipop
🍮 custard
🍯 honey pot
🍼 baby bottle
🥛 glass of milk
☕ hot beverage
🍵 teacup without handle
🍶 sake
🍾 bottle with popping cork
🍷 wine glass
🍸 cocktail glass
🍹 tropical drink
🍺 beer mug
🍻 clinking beer mugs
🥂 clinking glasses
🥃 tumbler glass
🥤 cup with straw
🧊 ice cube
🧋 bubble tea
🥢 chopsticks
🍽️ fork and knife with plate
🍴 fork and knife
🥄 spoon
🌍 globe showing europe-africa
🌎 globe showing americas
🌏 globe showing asia-australia
🌐 globe with meridians
🗾 map of japan
🏔️ snow-capped mountain
⛰️ mountain
🌋 volcano
🗻 mount fuji
🏕️ camping
🏖️ beach with umbrella
🏜️ desert
🏝️ desert island
🏞️ national park
🏟️ stadium
🏛️ classical building
🏗️ building construction
🧱 brick
🪨 rock
🪵 wood
🛖 hut
🏘️ houses
🏚️ derelict house
🏠 house
🏡 house with garden
🏢 office building
🏣 japanese post office
🏤 post office
🏥 hospital
🏦 bank
🏨 hotel
🏩 love hotel
🏪 convenience store
🏫 school
🏬 department store
🏭 factory
🏯 japanese castle
🏰 castle
💒 wedding
🗼 tokyo tower
🗽 statue of liberty
⛪ church
🕌 mosque
🛕 hindu temple
🕍 synagogue
⛩️ shinto shrine
🕋 kaaba
⛲ fountain
⛺ tent
☀️ sun
🌁 foggy
🌃 night with stars
🏙️ cityscape
🌄 sunrise over mountains
🌅 sunrise
🌆 cityscape at dusk
🌇 sunset
🌉 bridge at night
🎠 carousel horse
🎡 ferris wheel
🎢 roller coaster
💈 barber pole
🎪 circus tent
🚂 locomotive
🚃 railway car
🚄 high-speed train
🚅 bullet train
🚆 train
🚇 metro
🚈 light rail
🚉 station
🚊 tram
🚝 monorail
🚞 mountain railway
🚋 tram car
🚌 bus
🚍 oncoming bus
🚎 trolleybus
🚐 minibus
🚑 ambulance
🚒 fire engine
🚓 police car
🚔 oncoming police car
🚕 taxi
🚖 oncoming taxi
🚗 automobile
🚘 oncoming automobile
🚙 sport utility vehicle
🚚 delivery truck
🚛 articulated lorry
🚜 tractor
🛻 pickup truck
🏎️ racing car
🏍️ motorcycle
🛵 motor scooter
🛺 auto rickshaw
🚲 bicycle
🛴 kick scooter
🛹 skateboard
🛼 roller skate
🚏 bus stop
🛣️ motorway
🛤️ railway track
🛢️ oil drum
⛽ fuel pump
🚨 police car light
🚥 horizontal traffic light
🚦 vertical traffic light
🛑 stop sign
🚧 construction
⚓ anchor
⛵ sailboat
🛶 canoe
🚤 speedboat
🛳️ passenger ship
⛴️ ferry
🛥️ motor boat
🚢 ship
✈️ airplane
🛩️ small airplane
🛫 airplane departure
🛬 airplane arrival
🪂 parachute
💺 seat
🚁 helicopter
🚟 suspension railway
🚠 mountain cableway
🚡 aerial tramway
🛰️ satellite
🚀 rocket
🛸 flying saucer
🪐 ringed planet
🌠 shooting star
🌌 milky way
🌈 rainbow
🌂 closed umbrella
☂️ umbrella
☔ umbrella with rain drops
⛈️ cloud with lightning and rain
🌩️ cloud with lightning
🌪️ tornado
🌫️ fog
🌬️ wind face
🌀 cyclone
🌊 water wave
🎃 jack-o-lantern
🎄 christmas tree
🎆 fireworks
🎇 sparkler
✨ sparkles
🎈 balloon
🎉 party popper
🎊 confetti ball
🎋 tanabata tree
🎍 pine decoration
🎎 japanese dolls
🎏 carp streamer
🎐 wind chime
🎑 moon viewing ceremony
🧧 red envelope
🎀 ribbon
🎁 wrapped gift
🎗️ reminder ribbon
🎟️ admission tickets
🎫 ticket
🎖️ military medal
🏆 trophy
🏅 sports medal
🥇 1st place medal
🥈 2nd place medal
🥉 3rd place medal
⚽ soccer ball
⚾ baseball
🥎 softball
🏀 basketball
🏐 volleyball
🏈 american football
🏉 rugby football
🎾 tennis
🥏 flying disc
🎳 bowling
🏏 cricket game
🏑 field hockey
🏒 ice hockey
🥍 lacrosse
🏓 ping pong
🏸 badminton
🥊 boxing glove
🥋 martial arts uniform
🥅 goal net
⛳ flag in hole
⛸️ ice skate
🎣 fishing pole
🤿 diving mask
🎽 running shirt
🎿 skis
🛷 sled
🥌 curling stone
🎯 direct hit
🪀 yo-yo
🪁 kite
🎱 pool 8 ball
🔮 crystal ball
🎮 video game
🕹️ joystick
🎰 slot machine
🎲 game die
🧩 puzzle piece
🧸 teddy bear
🎭 performing arts
🖼️ framed picture
🎨 artist palette
🧵 thread
🧶 yarn
👓 glasses
🕶️ sunglasses
👔 necktie
👕 t-shirt
👖 jeans
🧣 scarf
🧤 gloves
🧥 coat
🧦 socks
👗 dress
👘 kimono
👙 bikini
👚 woman's clothes
👛 purse
👜 handbag
👝 clutch bag
🛍️ shopping bags
🎒 backpack
👞 man's shoe
👟 running shoe
🥾 hiking boot
🥿 flat shoe
👠 high-heeled shoe
👡 woman's sandal
👢 woman's boot
👑 crown
👒 woman's hat
🎩 top hat
🎓 graduation cap
🧢 billed cap
📿 prayer beads
💄 lipstick
💍 ring
💎 gem stone
🔇 muted speaker
🔈 speaker low volume
🔉 speaker medium volume
🔊 speaker high volume
📢 loudspeaker
📣 megaphone
📯 postal horn
🔔 bell
🔕 bell with slash
🎼 musical score
🎵 musical note
🎶 musical notes
🎙️ studio microphone
🎚️ level slider
🎛️ control knobs
🎤 microphone
🎧 headphone
📻 radio
🎷 saxophone
🎸 guitar
🎹 musical keyboard
🎺 trumpet
🎻 violin
🥁 drum
🪘 long drum
🪗 accordion
🪕 banjo
🪈 flute
📱 mobile phone
📲 mobile phone with arrow
☎️ telephone
📞 telephone receiver
📟 pager
📠 fax machine
🔋 battery
🔌 electric plug
💻 laptop
🖥️ desktop computer
🖨️ printer
⌨️ keyboard
🖱️ computer mouse
💽 computer disk
💾 floppy disk
💿 optical disk
📀 dvd
🎥 movie camera
🎞️ film frames
📽️ film projector
📺 television
📷 camera
📸 camera with flash
📹 video camera
📼 videocassette
🔍 magnifying glass tilted left
🔎 magnifying glass tilted right
🕯️ candle
💡 light bulb
🔦 flashlight
🏮 red paper lantern
📔 notebook with decorative cover
📕 closed book
📖 open book
📗 green book
📘 blue book
📙 orange book
📚 books
📓 notebook
📒 ledger
📃 page with curl
📜 scroll
📄 page facing up
📰 newspaper
📑 bookmark tabs
🔖 bookmark
🏷️ label
💰 money bag
💴 yen banknote
💵 dollar banknote
💶 euro banknote
💷 pound banknote
💸 money with wings
💳 credit card
💹 chart increasing with yen
💌 love letter
📧 e-mail
📨 incoming envelope
📩 envelope with arrow
📤 outbox tray
📥 inbox tray
📦 package
📫 closed mailbox with raised flag
📪 closed mailbox with lowered flag
📬 open mailbox with raised flag
📭 open mailbox with lowered flag
📮 postbox
🗳️ ballot box with ballot
✏️ pencil
✒️ black nib
🖋️ fountain pen
🖊️ pen
🖌️ paintbrush
🖍️ crayon
📝 memo
💼 briefcase
📁 file folder
📂 open file folder
📅 calendar
📆 tear-off calendar
📇 card index
📈 chart increasing
📉 chart decreasing
📊 bar chart
📋 clipboard
📌 pushpin
📍 round pushpin
📎 paperclip
📏 straight ruler
📐 triangular ruler
✂️ scissors
🗃️ card file box
🗄️ file cabinet
🗑️ wastebasket
🔒 locked
🔓 unlocked
🔏 locked with pen
🔐 locked with key
🔑 key
🗝️ old key
🔨 hammer
🪓 axe
⛏️ pick
🛠️ hammer and wrench
🪚 carpentry saw
🪛 screwdriver
🪜 ladder
🗡️ dagger
⚔️ crossed swords
🏹 bow and arrow
🛡️ shield
🔧 wrench
🔩 nut and bolt
⚙️ gear
🗜️ clamp
⚖️ balance scale
🔗 link
🧰 toolbox
🧲 magnet
🔬 microscope
🔭 telescope
📡 satellite antenna
💉 syringe
🩸 drop of blood
💊 pill
🩹 adhesive bandage
🩺 stethoscope
🩻 x-ray
🩼 crutch
🚪 door
🛗 elevator
🪞 mirror
🪟 window
🛏️ bed
🛋️ couch and lamp
🪑 chair
🚽 toilet
🚿 shower
🛁 bathtub
🪤 mouse trap
🪒 razor
🧴 lotion bottle
🧷 safety pin
🧹 broom
🧺 basket
🧻 roll of paper
🧼 soap
🧽 sponge
🧯 fire extinguisher
🛒 shopping cart
🪣 bucket
🪦 headstone
🪧 placard
🪩 mirror ball
🪬 hamsa
🫙 jar
🚬 cigarette
⚰️ coffin
⚱️ funeral urn
🗿 moai
🏧 atm sign
🚮 litter in bin sign
🚰 potable water
♿ wheelchair symbol
🚹 men's room
🚺 women's room
🚻 restroom
🚼 baby symbol
🚾 water closet
🛂 passport control
🛃 customs
🛄 baggage claim
🛅 left luggage
⛔ no entry
🚫 prohibited
🚳 no bicycles
🚭 no smoking
🚯 no littering
🚱 non-potable water
🚷 no pedestrians
📵 no mobile phones
🔞 no one under eighteen
☢️ radioactive
☣️ biohazard
☮️ peace symbol
☯️ yin yang
☸️ wheel of dharma
⚛️ atom symbol
⬆️ up arrow
↗️ up-right arrow
➡️ right arrow
↘️ down-right arrow
⬇️ down arrow
↙️ down-left arrow
⬅️ left arrow
↖️ up-left arrow
↕️ up-down arrow
↔️ left-right arrow
↩️ right arrow curving left
↪️ left arrow curving right
⤴️ right arrow curving up
⤵️ right arrow curving down
🔃 clockwise vertical arrows
🔄 counterclockwise arrows button
🔙 back arrow
🔚 end arrow
🔛 on arrow
🔜 soon arrow
🔝 top arrow
♈ aries
♉ taurus
♊ gemini
♋ cancer
♌ leo
♍ virgo
♎ libra
♏ scorpio
♐ sagittarius
♑ capricorn
♒ aquarius
♓ pisces
⛎ ophiuchus
🔀 shuffle tracks button
🔁 repeat button
🔂 repeat single button
▶️ play button
⏩ fast-forward button
⏭️ next track button
⏯️ play or pause button
◀️ reverse button
⏪ fast reverse button
⏮️ last track button
🔼 upwards button
⏫ fast upwards button
🔽 downwards button
⏬ fast downwards button
⏸️ pause button
⏹️ stop button
⏺️ record button
⏏️ eject button
🎦 cinema
🔅 dim button
🔆 bright button
📶 antenna bars
📳 vibration mode
📴 mobile phone off
♀️ female sign
♂️ male sign
✖️ multiply
➕ plus
➖ minus
➗ divide
♾️ infinity
‼️ double exclamation mark
⁉️ exclamation question mark
❓ question mark
❔ white question mark
❕ white exclamation mark
❗ exclamation mark
〰️ wavy dash
💱 currency exchange
💲 heavy dollar sign
⚕️ medical symbol
♻️ recycling symbol
⚜️ fleur-de-lis
🔱 trident emblem
📛 name badge
🔰 japanese symbol for beginner
⭕ hollow red circle
✅ check mark button
☑️ check box with check
✔️ check mark
❌ cross mark
❎ cross mark button
➰ curly loop
➿ double curly loop
〽️ part alternation mark
✳️ eight-spoked asterisk
✴️ eight-pointed star
❇️ sparkle
©️ copyright
®️ registered
™️ trade mark
#️⃣ keycap number sign
*️⃣ keycap asterisk
0️⃣ keycap 0
1️⃣ keycap 1
2️⃣ keycap 2
3️⃣ keycap 3
4️⃣ keycap 4
5️⃣ keycap 5
6️⃣ keycap 6
7️⃣ keycap 7
8️⃣ keycap 8
9️⃣ keycap 9
🔟 keycap 10
🔠 input latin uppercase
🔡 input latin lowercase
🔢 input numbers
🔣 input symbols
🔤 input latin letters
🅰️ a button blood type
🆎 ab button blood type
🅱️ b button blood type
🆑 cl button
🆒 cool button
🆓 free button
ℹ️ information
🆔 id button
Ⓜ️ circled m
🆕 new button
🆖 ng button
🅾️ o button blood type
🆗 ok button
🅿️ p button
🆘 sos button
🆙 up button
🆚 vs button
🈁 japanese here button
🈂️ japanese service charge button
🔴 red circle
🟠 orange circle
🟡 yellow circle
🟢 green circle
🔵 blue circle
🟣 purple circle
🟤 brown circle
⚫ black circle
⚪ white circle
🟥 red square
🟧 orange square
🟨 yellow square
🟩 green square
🟦 blue square
🟪 purple square
🟫 brown square
⬛ black large square
⬜ white large square
◼️ black medium square
◻️ white medium square
◾ black medium-small square
◽ white medium-small square
▪️ black small square
▫️ white small square
🔶 large orange diamond
🔷 large blue diamond
🔸 small orange diamond
🔹 small blue diamond
🔺 red triangle pointed up
🔻 red triangle pointed down
💠 diamond with a dot
🔘 radio button
🔳 white square button
🔲 black square button
🏁 chequered flag
🚩 triangular flag
🎌 crossed flags
🏴 black flag
🏳️ white flag
🏳️‍🌈 rainbow flag
🏳️‍⚧️ transgender flag
🏴‍☠️ pirate flag
🇦🇫 Afghanistan
🇦🇽 Îles d'Åland
🇦🇱 Albanie
🇩🇿 Algérie
🇦🇸 Samoa américaines
🇦🇩 Andorre
🇦🇴 Angola
🇦🇮 Anguilla
🇦🇶 Antarctique
🇦🇬 Antigua-et-Barbuda
🇦🇷 Argentine
🇦🇲 Arménie
🇦🇼 Aruba
🇦🇺 Australie
🇦🇹 Autriche
🇦🇿 Azerbaïdjan
🇧🇸 Bahamas
🇧🇭 Bahreïn
🇧🇩 Bangladesh
🇧🇧 Barbade
🇧🇾 Biélorussie
🇧🇪 Belgique
🇧🇿 Belize
🇧🇯 Bénin
🇧🇲 Bermudes
🇧🇹 Bhoutan
🇧🇴 Bolivie
🇧🇦 Bosnie-Herzégovine
🇧🇼 Botswana
🇧🇷 Brésil
🇮🇴 Territoire britannique de l'océan Indien
🇻🇬 Îles Vierges britanniques
🇧🇳 Brunei
🇧🇬 Bulgarie
🇧🇫 Burkina Faso
🇧🇮 Burundi
🇰🇭 Cambodge
🇨🇲 Cameroun
🇨🇦 Canada
🇮🇨 Îles Canaries
🇨🇻 Cap-Vert
🇧🇶 Pays-Bas caribéens
🇰🇾 Îles Caïmans
🇨🇫 République centrafricaine
🇹🇩 Tchad
🇨🇱 Chili
🇨🇳 Chine
🇨🇽 Île Christmas
🇨🇨 Îles Cocos
🇨🇴 Colombie
🇰🇲 Comores
🇨🇬 Congo-Brazzaville
🇨🇩 Congo-Kinshasa
🇨🇰 Îles Cook
🇨🇷 Costa Rica
🇨🇮 Côte d’Ivoire
🇭🇷 Croatie
🇨🇺 Cuba
🇨🇼 Curaçao
🇨🇾 Chypre
🇨🇿 Tchéquie
🇩🇰 Danemark
🇩🇯 Djibouti
🇩🇲 Dominique
🇩🇴 République dominicaine
🇪🇨 Équateur
🇪🇬 Égypte
🇸🇻 El Salvador
🇬🇶 Guinée équatoriale
🇪🇷 Érythrée
🇪🇪 Estonie
🇸🇿 Eswatini
🇪🇹 Éthiopie
🇪🇺 Union européenne
🇫🇰 Îles Malouines
🇫🇴 Îles Féroé
🇫🇯 Fidji
🇫🇮 Finlande
🇫🇷 France
🇬🇫 Guyane française
🇵🇫 Polynésie française
🇹🇫 Terres australes françaises
🇬🇦 Gabon
🇬🇲 Gambie
🇬🇪 Géorgie
🇩🇪 Allemagne
🇬🇭 Ghana
🇬🇮 Gibraltar
🇬🇷 Grèce
🇬🇱 Groenland
🇬🇩 Grenade
🇬🇵 Guadeloupe
🇬🇺 Guam
🇬🇹 Guatemala
🇬🇬 Guernesey
🇬🇳 Guinée
🇬🇼 Guinée-Bissau
🇬🇾 Guyana
🇭🇹 Haïti
🇭🇳 Honduras
🇭🇰 Hong Kong
🇭🇺 Hongrie
🇮🇸 Islande
🇮🇳 Inde
🇮🇩 Indonésie
🇮🇷 Iran
🇮🇶 Irak
🇮🇪 Irlande
🇮🇲 Île de Man
🇮🇱 Israël
🇮🇹 Italie
🇯🇲 Jamaïque
🇯🇵 Japon
🇯🇪 Jersey
🇯🇴 Jordanie
🇰🇿 Kazakhstan
🇰🇪 Kenya
🇰🇮 Kiribati
🇰🇼 Koweït
🇰🇬 Kirghizistan
🇱🇦 Laos
🇱🇻 Lettonie
🇱🇧 Liban
🇱🇸 Lesotho
🇱🇷 Liberia
🇱🇾 Libye
🇱🇮 Liechtenstein
🇱🇹 Lituanie
🇱🇺 Luxembourg
🇲🇴 Macao
🇲🇬 Madagascar
🇲🇼 Malawi
🇲🇾 Malaisie
🇲🇻 Maldives
🇲🇱 Mali
🇲🇹 Malte
🇲🇭 Îles Marshall
🇲🇶 Martinique
🇲🇷 Mauritanie
🇲🇺 Maurice
🇾🇹 Mayotte
🇲🇽 Mexique
🇫🇲 Micronésie
🇲🇩 Moldavie
🇲🇨 Monaco
🇲🇳 Mongolie
🇲🇪 Monténégro
🇲🇸 Montserrat
🇲🇦 Maroc
🇲🇿 Mozambique
🇲🇲 Myanmar (Birmanie)
🇳🇦 Namibie
🇳🇷 Nauru
🇳🇵 Népal
🇳🇱 Pays-Bas
🇳🇨 Nouvelle-Calédonie
🇳🇿 Nouvelle-Zélande
🇳🇮 Nicaragua
🇳🇪 Niger
🇳🇬 Nigeria
🇳🇺 Niue
🇳🇫 Île Norfolk
🇰🇵 Corée du Nord
🇲🇰 Macédoine du Nord
🇲🇵 Îles Mariannes du Nord
🇳🇴 Norvège
🇴🇲 Oman
🇵🇰 Pakistan
🇵🇼 Palaos
🇵🇸 Territoires palestiniens
🇵🇦 Panama
🇵🇬 Papouasie-Nouvelle-Guinée
🇵🇾 Paraguay
🇵🇪 Pérou
🇵🇭 Philippines
🇵🇳 Îles Pitcairn
🇵🇱 Pologne
🇵🇹 Portugal
🇵🇷 Porto Rico
🇶🇦 Qatar
🇷🇪 Réunion
🇷🇴 Roumanie
🇷🇺 Russie
🇷🇼 Rwanda
🇼🇸 Samoa
🇸🇲 Saint-Marin
🇸🇹 Sao Tomé-et-Principe
🇸🇦 Arabie saoudite
🇸🇳 Sénégal
🇷🇸 Serbie
🇸🇨 Seychelles
🇸🇱 Sierra Leone
🇸🇬 Singapour
🇸🇽 Saint-Martin (partie néerlandaise)
🇸🇰 Slovaquie
🇸🇮 Slovénie
🇸🇧 Îles Salomon
🇸🇴 Somalie
🇿🇦 Afrique du Sud
🇬🇸 Géorgie du Sud et îles Sandwich du Sud
🇰🇷 Corée du Sud
🇸🇸 Soudan du Sud
🇪🇸 Espagne
🇱🇰 Sri Lanka
🇧🇱 Saint-Barthélemy
🇸🇭 Sainte-Hélène
🇰🇳 Saint-Kitts-et-Nevis
🇱🇨 Sainte-Lucie
🇲🇫 Saint-Martin (partie française)
🇵🇲 Saint-Pierre-et-Miquelon
🇻🇨 Saint-Vincent-et-les-Grenadines
🇸🇩 Soudan
🇸🇷 Suriname
🇸🇯 Svalbard et Jan Mayen
🇸🇪 Suède
🇨🇭 Suisse
🇸🇾 Syrie
🇹🇼 Taïwan
🇹🇯 Tadjikistan
🇹🇿 Tanzanie
🇹🇭 Thaïlande
🇹🇱 Timor oriental
🇹🇬 Togo
🇹🇰 Tokelau
🇹🇴 Tonga
🇹🇹 Trinité-et-Tobago
🇹🇳 Tunisie
🇹🇷 Turquie
🇹🇲 Turkménistan
🇹🇨 Îles Turques-et-Caïques
🇹🇻 Tuvalu
🇻🇮 Îles Vierges des États-Unis
🇺🇬 Ouganda
🇺🇦 Ukraine
🇦🇪 Émirats arabes unis
🇬🇧 Royaume-Uni
🇺🇳 Nations Unies
🇺🇸 États-Unis
🇺🇾 Uruguay
🇺🇿 Ouzbékistan
🇻🇺 Vanuatu
🇻🇦 Vatican
🇻🇪 Venezuela
🇻🇳 Vietnam
🇼🇫 Wallis-et-Futuna
🇪🇭 Sahara occidental
🇾🇪 Yémen
🇿🇲 Zambie
🇿🇼 Zimbabwe
  '';
  home.packages = with pkgs; [
    # --- emoji-picker ---
    (pkgs.writeShellScriptBin "emoji-picker" ''
      if pgrep -x rofi > /dev/null; then
        pkill -x rofi
        exit 0
      fi
      EMOJI=$(awk '{name=""; for(i=2;i<=NF;i++) name=name (i>2?" ":"") $i; print $1 "	" name}' ~/.config/rofi/emoji-data | rofi -dmenu -i -separator "	" -columns 2 -display-columns 1 -p "󰞅 " -theme ~/.config/rofi/emoji.rasi | cut -f1)
      if [ -n "$EMOJI" ]; then
        echo -n "$EMOJI" | wl-copy
        while pgrep -x rofi > /dev/null; do
          sleep 0.05
        done
        sleep 0.2
        wtype -M ctrl -k v -m ctrl
      fi
    '')
  ];
}
