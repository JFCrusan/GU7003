#include "GU7003.h"

GU7003::GU7003(uint8_t resetPin, uint8_t busyPin)
{
  _resetPin = resetPin;
  _busyPin = busyPin;
}

void GU7003::begin()
{
  pinMode(_resetPin, OUTPUT);
  pinMode(_busyPin, INPUT);

  digitalWrite(_resetPin, LOW);

  Serial.begin(38400);

  delay(1000);

  digitalWrite(_resetPin, HIGH);

  delay(500);

  clear();

  cursorOff();
  setBrightness(8);
  setFontSize(1, 1);
}

void GU7003::write(uint8_t data)
{
  while (digitalRead(_busyPin) == HIGH)
  {
  }

  Serial.write(data);
}

void GU7003::clear()
{
  write(0x0C);
  delay(100);
}

void GU7003::home()
{
  write(0x0B);
  delay(20);
}

void GU7003::cursorOn()
{
  write(0x1F);
  write(0x43);
  write(0x01);
  delay(20);
}

void GU7003::cursorOff()
{
  write(0x1F);
  write(0x43);
  write(0x00);
  delay(20);
}

void GU7003::setBrightness(uint8_t level)
{
  if (level < 1) level = 1;
  if (level > 8) level = 8;

  write(0x1F);
  write(0x58);
  write(level);

  delay(50);
}

void GU7003::setFontSize(uint8_t width, uint8_t height)
{
  write(0x1F);
  write(0x28);
  write(0x67);
  write(0x40);

  write(width);
  write(height);

  delay(100);
}

void GU7003::setCursor(uint16_t x, uint16_t y)
{
  write(0x1F);
  write(0x24);

  write(x & 0xFF);
  write((x >> 8) & 0xFF);

  write(y & 0xFF);
  write((y >> 8) & 0xFF);

  delay(50);
}

void GU7003::powerSave(bool enable)
{
  write(0x1F);
  write(0x28);
  write(0x61);
  write(0x40);

  write(enable ? 0x00 : 0x01);

  delay(100);
}

void GU7003::print(const char *text)
{
  while (*text)
  {
    write(*text++);
  }
}

void GU7003::print(int number)
{
  char b[16];
  ltoa((long)number, b, 10);
  print(b);
}

void GU7003::print(unsigned int number)
{
  char b[16];
  ultoa((unsigned long)number, b, 10);
  print(b);
}

void GU7003::print(long number)
{
  char b[16];
  ltoa(number, b, 10);
  print(b);
}

void GU7003::print(unsigned long number)
{
  char b[16];
  ultoa(number, b, 10);
  print(b);
}

void GU7003::print(float number, uint8_t decimals)
{
  char b[24];
  dtostrf(number, 0, decimals, b);
  print(b);
}

void GU7003::println(const char *text)
{
  print(text);
  setCursor(0, 1);
}
