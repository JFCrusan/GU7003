#ifndef GU7003_H
#define GU7003_H

#include <Arduino.h>

class GU7003
{
public:
  static const uint16_t DISPLAY_WIDTH = 112;
  static const uint8_t DISPLAY_HEIGHT = 16;
  static const uint16_t DISPLAY_MEMORY_WIDTH = 512;
  static const uint16_t DISPLAY_MEMORY_BYTES = 1024;
  static const uint8_t BLINK_TICK_MS = 14;

  enum class BlinkMode : uint8_t
  {
    NormalBlank = 0x01,
    NormalReverse = 0x02
  };

  enum class WriteMixtureMode : uint8_t
  {
    Normal = 0,
    OR = 1,
    AND = 2,
    XOR = 3
  };

  enum class WriteMode : uint8_t
  {
    Overwrite = 0x01,
    VerticalScroll = 0x02,
    HorizontalScroll = 0x03
  };

  enum class WriteScreenMode : uint8_t
  {
    Display = 0x00,
    All = 0x01
  };

  GU7003(uint8_t resetPin, uint8_t busyPin);

  void begin();

  void clear();
  void home();

  void cursorOn();
  void cursorOff();

  void setBrightness(uint8_t level);
  void setFontSize(uint8_t width, uint8_t height);
  void setCharacterSpacing(uint8_t mode);
  void setCursor(uint16_t x, uint16_t y);

  // Native GU-7000 user windows. Window 0 is the base window; user window
  // numbers are 1 through 4. Y positions and heights use 8-dot units.
  void defineUserWindow(uint8_t window, uint16_t x, uint16_t y,
                        uint16_t width, uint16_t heightBytes);
  void selectWindow(uint8_t window);
  void cancelUserWindow(uint8_t window);

  void powerSave(bool enable);
  // Compatibility API: this sends the native screen-saver command.
  void screenMode(uint8_t mode);
  void setWriteScreenMode(WriteScreenMode mode);
  void reverse(bool enable);
  void setWriteMixtureMode(WriteMixtureMode mode);

  void setWriteMode(WriteMode mode);
  void setHorizontalScrollSpeed(uint8_t speed);

  // Native display-memory scroll. On this 16-dot-high module, shiftBytes=2
  // shifts left by one pixel. speedTicks are approximately 14 ms each.
  void scrollDisplay(uint16_t shiftBytes, uint16_t cycles,
                     uint8_t speedTicks);

  // Blink times are expressed in approximately 14 ms hardware ticks.
  // blink() runs for 1..255 cycles; zero values are clamped to one.
  void blink(BlinkMode mode, uint8_t normalTicks,
             uint8_t alternateTicks, uint8_t cycles);
  void blinkContinuous(BlinkMode mode, uint8_t normalTicks,
                       uint8_t alternateTicks);
  void stopBlink();

  // Low-level native GU-7000 bitmap calls.
  // heightBytes is 1 for 8 dots high or 2 for 16 dots high.
  void drawBitmapNativeRAM(uint16_t x, uint8_t width,
                           uint8_t heightBytes, const uint8_t *data);
  void drawBitmapNative_P(uint16_t x, uint8_t width,
                          uint8_t heightBytes, const uint8_t *data);

  // Friendly row-major bitmap call.
  // Each source row contains ceil(width/8) bytes.
  // Bit 7 is the left-most pixel in each source byte.
  // x/y are normal display pixel coordinates.
  void drawBitmap_P(uint16_t x, uint8_t y,
                    uint8_t width, uint8_t height,
                    const uint8_t *rowMajorData);

  void print(const char *text);
  void print(int number);
  void print(unsigned int number);
  void print(long number);
  void print(unsigned long number);
  void print(float number, uint8_t decimals);
  void println(const char *text);

private:
  void write(uint8_t data);
  void sendBlinkCommand(uint8_t pattern, uint8_t normalTicks,
                        uint8_t alternateTicks, uint8_t cycles);
  void beginNativeBitmap(uint16_t x, uint8_t width, uint8_t heightBytes);

  uint8_t _resetPin;
  uint8_t _busyPin;
  uint8_t _currentWindow;
};

#endif
