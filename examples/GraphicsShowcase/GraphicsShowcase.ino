#include <GU7003.h>
#include <avr/pgmspace.h>

// GU7003 v1.1 friendly graphics API showcase.
// UP/A2 = next screen. DOWN/A4 = previous screen.

GU7003 vfd(10, 12);

const int UP_BUTTON = A2;
const int DOWN_BUTTON = A4;
const unsigned long DEBOUNCE_MS = 20;

bool upRaw = HIGH, upStable = HIGH;
bool downRaw = HIGH, downStable = HIGH;
unsigned long upChanged = 0, downChanged = 0;
uint8_t screenNumber = 0;

// Human-readable row-major icons.
// Each quoted visual row corresponds directly to one bitmap row.

// 7x7 right pointer:
// ...#...
// ...##..
// #######
// #######
// ...##..
// ...#...
// .......
const uint8_t POINTER_RIGHT[] PROGMEM = {
  0x10,
  0x18,
  0xFE,
  0xFE,
  0x18,
  0x10,
  0x00
};

// 8x8 warning diamond:
// ...##...
// ..####..
// .######.
// ########
// ########
// .######.
// ..####..
// ...##...
const uint8_t WARNING_DIAMOND[] PROGMEM = {
  0x18, 0x3C, 0x7E, 0xFF,
  0xFF, 0x7E, 0x3C, 0x18
};

// 8x8 primer-ish cartridge icon:
// ..####..
// .######.
// .##..##.
// .##..##.
// .##..##.
// .##..##.
// .######.
// ..####..
const uint8_t PRIMER_ICON[] PROGMEM = {
  0x3C, 0x7E, 0x66, 0x66,
  0x66, 0x66, 0x7E, 0x3C
};

// 8x8 check:
// ........
// ......#.
// .....##.
// #...##..
// ##.##...
// .###....
// ..#.....
// ........
const uint8_t CHECK_ICON[] PROGMEM = {
  0x00, 0x02, 0x06, 0x8C,
  0xD8, 0x70, 0x20, 0x00
};

bool pressed(int pin, bool &lastRaw, bool &stable, unsigned long &changed)
{
  bool raw = digitalRead(pin);
  unsigned long now = millis();

  if (raw != lastRaw) {
    lastRaw = raw;
    changed = now;
  }

  if (now - changed < DEBOUNCE_MS) return false;
  if (raw == stable) return false;

  stable = raw;
  return stable == LOW;
}

void clean()
{
  vfd.reverse(false);
  vfd.clear();
  vfd.setFontSize(1, 1);
  vfd.setCharacterSpacing(0);
}

void screen0()
{
  clean();
  vfd.setCursor(0, 0);
  vfd.print("GRAPHICS API");
  vfd.setCursor(0, 8);
  vfd.print("v1.1 TEST");
}

void screen1()
{
  clean();

  // Same pointer at four arbitrary Y positions.
  vfd.drawBitmap_P(5,  0, 7, 7, POINTER_RIGHT);
  vfd.drawBitmap_P(30, 3, 7, 7, POINTER_RIGHT);
  vfd.drawBitmap_P(55, 6, 7, 7, POINTER_RIGHT);
  vfd.drawBitmap_P(80, 9, 7, 7, POINTER_RIGHT);
}

void screen2()
{
  clean();

  vfd.drawBitmap_P(4,  0, 8, 8, WARNING_DIAMOND);
  vfd.drawBitmap_P(28, 8, 8, 8, PRIMER_ICON);
  vfd.drawBitmap_P(52, 4, 8, 8, CHECK_ICON);
  vfd.drawBitmap_P(80, 1, 7, 7, POINTER_RIGHT);
}

void screen3()
{
  clean();

  // Prototype of an edit pointer beside text.
  vfd.drawBitmap_P(0, 1, 7, 7, POINTER_RIGHT);
  vfd.setCursor(12, 0);
  vfd.print("MAIN 123");

  vfd.drawBitmap_P(0, 9, 7, 7, POINTER_RIGHT);
  vfd.setCursor(12, 8);
  vfd.print("PRIMER 100");
}

void drawScreen()
{
  switch (screenNumber) {
    case 0: screen0(); break;
    case 1: screen1(); break;
    case 2: screen2(); break;
    case 3: screen3(); break;
  }
}

void setup()
{
  pinMode(UP_BUTTON, INPUT_PULLUP);
  pinMode(DOWN_BUTTON, INPUT_PULLUP);

  vfd.begin();
  vfd.cursorOff();
  vfd.setBrightness(8);

  drawScreen();
}

void loop()
{
  if (pressed(UP_BUTTON, upRaw, upStable, upChanged)) {
    screenNumber = (screenNumber + 1) % 4;
    drawScreen();
  }

  if (pressed(DOWN_BUTTON, downRaw, downStable, downChanged)) {
    screenNumber = (screenNumber == 0) ? 3 : screenNumber - 1;
    drawScreen();
  }
}
