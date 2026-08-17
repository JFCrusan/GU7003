#include <GU7003.h>
#include <avr/pgmspace.h>

GU7003 vfd(10, 12);

// Column-major 24x16 native bitmap: an asymmetric, non-character sprite.
// Each column contains the upper eight dots followed by the lower eight.
const uint8_t sprite[] PROGMEM = {
  0x03, 0xC0, 0x07, 0xE0, 0x2F, 0xF4, 0x1D, 0xB8,
  0x1D, 0xB8, 0x37, 0xEC, 0x7F, 0xFE, 0xFF, 0xEB,
  0xFF, 0xEB, 0x7F, 0xFE, 0x37, 0xEC, 0x1D, 0xB8,
  0x1D, 0xB8, 0x2F, 0xF4, 0x07, 0xE0, 0x03, 0xC0,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
};

const uint16_t SPRITE_X = 136;
const uint8_t SPRITE_WIDTH = 24;
const uint16_t SCROLL_CYCLES = 176;

void preloadSprite()
{
  vfd.selectWindow(0);
  vfd.setWriteMode(GU7003::WriteMode::Overwrite);
  vfd.setWriteScreenMode(GU7003::WriteScreenMode::All);
  vfd.setCursor(0, 0);
  vfd.clear();
  vfd.drawBitmapNative_P(SPRITE_X, SPRITE_WIDTH, 2, sprite);
}

void setup()
{
  vfd.begin();
}

void loop()
{
  preloadSprite();
  delay(350);

  // Two memory bytes are one 16-dot column. The controller moves the
  // preloaded bitmap left one pixel per cycle without software redraws.
  vfd.scrollDisplay(2, SCROLL_CYCLES, 1);
  delay(2700);

  // Restore the 512-pixel ring origin instantly for the next clean pass.
  vfd.scrollDisplay(2, GU7003::DISPLAY_MEMORY_WIDTH - SCROLL_CYCLES, 0);
  delay(150);
}
