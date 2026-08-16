#include <GU7003.h>

// Native user-window showcase for the 112x16 GU7003.
// Each phase remains visible for the focused webcam HIL test.

GU7003 vfd(10, 12);

const unsigned long PHASE_MS = 15000;

void setup()
{
  vfd.begin();
  vfd.setBrightness(8);
  vfd.setFontSize(1, 1);
  vfd.setCharacterSpacing(0);

  // Split the display into independent 112x8 top and bottom windows.
  vfd.defineUserWindow(1, 0, 0, GU7003::DISPLAY_WIDTH, 1);
  vfd.defineUserWindow(2, 0, 1, GU7003::DISPLAY_WIDTH, 1);

  vfd.selectWindow(1);
  vfd.home();
  vfd.print("WINDOW ONE");

  vfd.selectWindow(2);
  vfd.home();
  vfd.print("WINDOW TWO");
  delay(PHASE_MS);

  // Clearing and rewriting window 1 must leave window 2 unchanged.
  vfd.selectWindow(1);
  vfd.clear();
  vfd.print("ONE UPDATED");
  delay(PHASE_MS);

  // Cancel the non-current window first. Canceling the current window then
  // restores the base window before the full-screen message is written.
  vfd.selectWindow(2);
  vfd.cancelUserWindow(1);
  vfd.cancelUserWindow(2);

  // No selectWindow(0) here: cancelUserWindow() guarantees restoration when
  // the canceled window was current.
  vfd.clear();
  vfd.print("BASE ACTIVE\r\nWINDOWS OFF");
}

void loop()
{
}
