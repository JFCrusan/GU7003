#include <GU7003.h>

GU7003 vfd(10, 12);

void pauseDemo(unsigned long ms)
{
  delay(ms);
}

void demo()
{
  // 1. CLEAR
  vfd.clear();
  vfd.setFontSize(1, 1);
  vfd.setCursor(0, 0);
  vfd.print("CLEAR");
  pauseDemo(2000);

  // 2. HOME
  vfd.clear();
  vfd.setCursor(50, 0);
  vfd.print("HOME");
  delay(1000);
  vfd.home();
  vfd.print("H");
  pauseDemo(2000);

  // 3. CURSOR OFF
  vfd.clear();
  vfd.cursorOff();
  vfd.setCursor(0, 0);
  vfd.print("CURSOR OFF");
  pauseDemo(2000);

  // 4. CURSOR ON
  vfd.clear();
  vfd.cursorOn();
  vfd.setCursor(0, 0);
  vfd.print("CURSOR ON");
  pauseDemo(3000);

  // 5. CURSOR OFF AGAIN
  vfd.cursorOff();
  vfd.clear();
  vfd.setCursor(0, 0);
  vfd.print("CURSOR OFF");
  pauseDemo(2000);

  // 6. BRIGHTNESS
  vfd.clear();
  vfd.setFontSize(1, 1);

  for (uint8_t level = 1; level <= 8; level++)
  {
    vfd.clear();
    vfd.setBrightness(level);
    vfd.setCursor(0, 0);
    vfd.print("BRIGHTNESS: ");
    vfd.print((int)level);
    delay(1500);
  }

  pauseDemo(1000);

  // 7. FONT 1x1
  vfd.clear();
  vfd.setFontSize(1, 1);
  vfd.setCursor(0, 0);
  vfd.print("1x1");
  pauseDemo(2500);

  // 8. FONT 2x2
  vfd.clear();
  vfd.setFontSize(2, 2);
  vfd.setCursor(0, 0);
  vfd.print("2x2");
  pauseDemo(2500);

  // 9. FONT 3x2
  vfd.clear();
  vfd.setFontSize(3, 2);
  vfd.setCursor(0, 0);
  vfd.print("3x2");
  pauseDemo(2500);

  // 10. SET CURSOR
  vfd.clear();
  vfd.setFontSize(1, 1);
  vfd.setCursor(0, 0);
  vfd.print("LEFT");
  vfd.setCursor(60, 0);
  vfd.print("RIGHT");
  pauseDemo(2500);

  // 11. PRINT STRING
  vfd.clear();
  vfd.setCursor(0, 0);
  vfd.print("STRING TEST");
  pauseDemo(2000);

  // 12. PRINT INTEGER
  vfd.clear();
  vfd.setCursor(0, 0);
  vfd.print("INTEGER: ");
  vfd.print(12345);
  pauseDemo(2000);

  // 13. PRINT UNSIGNED INTEGER
  vfd.clear();
  vfd.setCursor(0, 0);
  vfd.print("UNSIGNED:");
  vfd.setCursor(0, 1);
  unsigned long value = 4294967295UL;
  vfd.print(value);
  pauseDemo(2000);

  // 14. PRINT FLOAT
  vfd.clear();
  vfd.setCursor(0, 0);
  vfd.print("FLOAT: ");
  vfd.print(123.456, 2);
  pauseDemo(2000);

  // 15. PRINTLN
  vfd.clear();
  vfd.setFontSize(1, 1);
  vfd.setCursor(0, 0);
  vfd.println("PRINTLN");
  vfd.print("NEXT");
  pauseDemo(2500);

  // 16. POWER SAVE
  vfd.clear();
  vfd.setCursor(0, 0);
  vfd.print("POWER SAVE");
  pauseDemo(2000);
  vfd.powerSave(true);
  pauseDemo(3000);
  vfd.powerSave(false);
  pauseDemo(1000);

  // 17. WAKE
  vfd.clear();
  vfd.setCursor(0, 0);
  vfd.print("WAKE");
  pauseDemo(2500);

  // 18. COMBINED TEST
  vfd.clear();
  vfd.setBrightness(8);
  vfd.setFontSize(1, 1);
  vfd.cursorOff();
  vfd.setCursor(0, 0);
  vfd.print("GU7003");
  vfd.setCursor(60, 0);
  vfd.print("OK");
  pauseDemo(3000);

  // DONE
  vfd.clear();
  vfd.setCursor(0, 0);
  vfd.print("DEMO COMPLETE");
  pauseDemo(2500);
}

void setup()
{
  vfd.begin();
}

void loop()
{
  demo();
}
