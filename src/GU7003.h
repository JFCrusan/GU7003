#ifndef GU7003_H
#define GU7003_H

#include <Arduino.h>

class GU7003
{
public:
  GU7003(uint8_t resetPin, uint8_t busyPin);

  void begin();

  void clear();
  void home();

  void cursorOn();
  void cursorOff();

  void setBrightness(uint8_t level);
  void setFontSize(uint8_t width, uint8_t height);
  void setCursor(uint16_t x, uint16_t y);

  void powerSave(bool enable);

  void print(const char *text);
  void print(int number);
  void print(unsigned int number);
  void print(long number);
  void print(unsigned long number);
  void print(float number, uint8_t decimals);

  void println(const char *text);

private:
  void write(uint8_t data);

  uint8_t _resetPin;
  uint8_t _busyPin;
};

#endif
