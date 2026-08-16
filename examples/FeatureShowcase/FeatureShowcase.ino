#include <GU7003.h>
#include <avr/pgmspace.h>

// Forever-looping showroom sequence for the Noritake GU112X16G-7003.
// The fixed phase lengths also give the focused HIL runner deterministic
// observation windows without adding test-only behavior to the example.

GU7003 vfd(10, 12);

static const uint8_t ONE_SECOND_TICKS = 71;
static const unsigned long TITLE_MS = 9000;
static const unsigned long TEXT_MS = 8000;
static const unsigned long STEP_MS = 4000;
static const unsigned long BLINK_MS = 8000;
static const unsigned long WINDOW_MS = 7000;

// A 16x16 diamond and 8x8 check, stored row-major in flash.
const uint8_t DIAMOND_16[] PROGMEM = {
  0x00, 0x00, 0x01, 0x80, 0x03, 0xC0, 0x07, 0xE0,
  0x0F, 0xF0, 0x1F, 0xF8, 0x3F, 0xFC, 0x7F, 0xFE,
  0xFF, 0xFF, 0x7F, 0xFE, 0x3F, 0xFC, 0x1F, 0xF8,
  0x0F, 0xF0, 0x07, 0xE0, 0x03, 0xC0, 0x01, 0x80
};

const uint8_t CHECK_8[] PROGMEM = {
  0x00, 0x02, 0x06, 0x8C, 0xD8, 0x70, 0x20, 0x00
};

static const uint8_t SWATCH_WIDTH = 20;
uint8_t swatchBackground[SWATCH_WIDTH * 2];
uint8_t swatchOverlay[SWATCH_WIDTH * 2];

void resetControllerState()
{
  // Make every phase independent so the sequence is deterministic on every
  // loop, including after the user-window and native-blink demonstrations.
  vfd.selectWindow(0);
  vfd.cancelUserWindow(1);
  vfd.cancelUserWindow(2);
  vfd.selectWindow(0);
  vfd.stopBlink();
  vfd.reverse(false);
  vfd.screenMode(1);
  vfd.setBrightness(8);
  vfd.setFontSize(1, 1);
  vfd.setCharacterSpacing(0);
  vfd.setWriteMixtureMode(GU7003::WriteMixtureMode::Normal);
  vfd.cursorOff();
  vfd.clear();
}

void showTitle()
{
  resetControllerState();
  vfd.setCursor(35, 0);
  vfd.print("FEATURE");
  vfd.setCursor(32, 1);
  vfd.print("SHOWCASE");
  delay(TITLE_MS);
}

void showTypography()
{
  resetControllerState();
  vfd.setCursor(5, 0);
  vfd.print("1X1 SMALL");
  vfd.setFontSize(2, 1);
  vfd.setCursor(5, 1);
  vfd.print("2X1 BOLD");
  delay(TEXT_MS);
}

void writeBrightnessLevel(uint8_t level)
{
  vfd.setBrightness(level);
  vfd.setCursor(34, 1);
  vfd.print("LEVEL ");
  vfd.print((int)level);
}

void showBrightnessSweep()
{
  resetControllerState();
  vfd.setCursor(26, 0);
  vfd.print("BRIGHTNESS");

  // Same-pixel rewrites make the sweep clean without flashing full clears.
  writeBrightnessLevel(2);
  delay(STEP_MS);
  writeBrightnessLevel(5);
  delay(STEP_MS);
  writeBrightnessLevel(8);
  delay(STEP_MS);
}

void showReverseMode()
{
  resetControllerState();
  vfd.setCursor(20, 0);
  vfd.print("REVERSE MODE");
  vfd.setCursor(29, 1);
  vfd.print("NORMAL");
  delay(2000);

  // Reverse affects subsequent character writes on this controller. Redraw
  // the complete card in reverse so no normal cells remain mixed into it.
  vfd.reverse(true);
  vfd.clear();
  vfd.setCursor(20, 0);
  vfd.print("REVERSE MODE");
  vfd.setCursor(32, 1);
  vfd.print("INVERTED");
  delay(4000);

  vfd.reverse(false);
  vfd.clear();
  vfd.setCursor(20, 0);
  vfd.print("REVERSE MODE");
  vfd.setCursor(32, 1);
  vfd.print("RESTORED");
  delay(4000);
}

void showBlink(GU7003::BlinkMode mode, const char *bottomRow,
               uint8_t bottomX)
{
  resetControllerState();
  vfd.setCursor(20, 0);
  vfd.print("NATIVE BLINK");
  vfd.setCursor(bottomX, 1);
  vfd.print(bottomRow);
  delay(1000);

  vfd.blinkContinuous(mode, ONE_SECOND_TICKS, ONE_SECOND_TICKS);
  delay(BLINK_MS);
  vfd.stopBlink();
  delay(1000);
}

void showGraphics()
{
  resetControllerState();

  vfd.drawBitmap_P(0, 0, 16, 16, DIAMOND_16);
  vfd.drawBitmap_P(103, 4, 8, 8, CHECK_8);
  vfd.setCursor(22, 0);
  vfd.print("GRAPHICS");
  vfd.setCursor(22, 1);
  vfd.print("PIXELS + ART");
  delay(TEXT_MS);
}

void fillSwatch(uint8_t *data, uint8_t pattern)
{
  for (uint8_t i = 0; i < SWATCH_WIDTH * 2; ++i)
    data[i] = pattern;
}

void compositeSwatch(uint8_t x, GU7003::WriteMixtureMode mode)
{
  vfd.setWriteMixtureMode(GU7003::WriteMixtureMode::Normal);
  vfd.drawBitmapNativeRAM(x, SWATCH_WIDTH, 2, swatchBackground);
  vfd.setWriteMixtureMode(mode);
  vfd.drawBitmapNativeRAM(x, SWATCH_WIDTH, 2, swatchOverlay);
}

void showWriteMixture()
{
  resetControllerState();

  compositeSwatch(0, GU7003::WriteMixtureMode::Normal);
  compositeSwatch(30, GU7003::WriteMixtureMode::OR);
  compositeSwatch(60, GU7003::WriteMixtureMode::AND);
  compositeSwatch(90, GU7003::WriteMixtureMode::XOR);

  // Restore normal writes before labeling the four distinct results.
  vfd.setWriteMixtureMode(GU7003::WriteMixtureMode::Normal);
  vfd.setCursor(5, 0);
  vfd.print("N");
  vfd.setCursor(33, 0);
  vfd.print("OR");
  vfd.setCursor(61, 0);
  vfd.print("AND");
  vfd.setCursor(91, 0);
  vfd.print("XOR");
  delay(TEXT_MS);
}

void showUserWindows()
{
  resetControllerState();
  vfd.defineUserWindow(1, 0, 0, GU7003::DISPLAY_WIDTH, 1);
  vfd.defineUserWindow(2, 0, 1, GU7003::DISPLAY_WIDTH, 1);

  vfd.selectWindow(1);
  vfd.home();
  vfd.print("WINDOW ONE");
  vfd.selectWindow(2);
  vfd.home();
  vfd.print("WINDOW TWO");
  delay(WINDOW_MS);

  // Only window 1 is cleared and rewritten; window 2 must remain unchanged.
  vfd.selectWindow(1);
  vfd.clear();
  vfd.home();
  vfd.print("ONE UPDATED");
  delay(WINDOW_MS);

  // Canceling the selected window guarantees a clean return to base window 0.
  vfd.selectWindow(2);
  vfd.cancelUserWindow(1);
  vfd.cancelUserWindow(2);
  vfd.setWriteMixtureMode(GU7003::WriteMixtureMode::Normal);
  vfd.reverse(false);
  vfd.setFontSize(1, 1);
  vfd.setCharacterSpacing(0);
  vfd.clear();
  vfd.setCursor(0, 0);
  vfd.print("BASE RESTORED");
  vfd.setCursor(0, 1);
  vfd.print("WINDOWS OFF");
  delay(WINDOW_MS);
}

void showFinale()
{
  resetControllerState();
  vfd.setCursor(32, 0);
  vfd.print("SHOWCASE");
  vfd.setCursor(26, 1);
  vfd.print("LOOPING...");
  delay(TEXT_MS);
}

void setup()
{
  fillSwatch(swatchBackground, 0xF0);
  fillSwatch(swatchOverlay, 0xCC);
  vfd.begin();
}

void loop()
{
  showTitle();
  showTypography();
  showBrightnessSweep();
  showReverseMode();
  showBlink(GU7003::BlinkMode::NormalBlank, "NORMAL / BLANK", 14);
  showBlink(GU7003::BlinkMode::NormalReverse, "NORMAL / REVERSE", 8);
  showGraphics();
  showWriteMixture();
  showUserWindows();
  showFinale();
}
