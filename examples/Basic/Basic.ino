#include <GU7003.h>

GU7003 vfd(10, 12);

void setup()
{
  vfd.begin();

  vfd.setBrightness(8);
  vfd.setFontSize(1, 1);
  vfd.setCursor(0, 0);
  vfd.print("Hello World");
}

void loop()
{
}
