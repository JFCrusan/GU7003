#include <GU7003.h>

GU7003 vfd(10, 12);

void resetDisplay()
{
  vfd.selectWindow(0);
  vfd.setWriteMode(GU7003::WriteMode::Overwrite);
  vfd.setWriteScreenMode(GU7003::WriteScreenMode::Display);
  vfd.setCharacterSpacing(0);
  // A hidden-memory preload leaves the cursor in that area. Explicitly move
  // it back before clearing, because Display mode scopes actions by cursor.
  vfd.setCursor(0, 0);
  vfd.clear();
}

void showMemoryScroll()
{
  resetDisplay();
  vfd.setWriteScreenMode(GU7003::WriteScreenMode::All);

  // Preload text just beyond the 112 visible columns, then reveal it from
  // the controller's 400-column hidden area one pixel at a time.
  vfd.setCursor(GU7003::DISPLAY_WIDTH, 0);
  vfd.print("NATIVE ACTION");
  vfd.setCursor(GU7003::DISPLAY_WIDTH, 1);
  vfd.print("512X16 MEMORY");
  vfd.scrollDisplay(2, 210, 2);
  delay(1000);

  // The scroll action leaves the display-memory origin shifted. Complete the
  // 512-pixel ring instantly so following cursor writes are visible at x=0.
  vfd.scrollDisplay(2, GU7003::DISPLAY_MEMORY_WIDTH - 210, 0);
}

void showHorizontalWriteScroll()
{
  resetDisplay();
  vfd.setHorizontalScrollSpeed(4);
  vfd.setWriteMode(GU7003::WriteMode::HorizontalScroll);
  vfd.home();
  vfd.print("HORIZONTAL NATIVE CHARACTER SCROLL");
  delay(1500);
}

void showVerticalWriteScroll()
{
  resetDisplay();
  vfd.setWriteMode(GU7003::WriteMode::VerticalScroll);
  vfd.setCursor(0, 0);
  vfd.print("VERTICAL ONE");
  vfd.setCursor(0, 1);
  vfd.print("VERTICAL TWO.....X");
  delay(1000);

  // The next character has no room on the bottom row, so the controller
  // scrolls that row upward and opens a new bottom row.
  vfd.print("VERTICAL THREE");
  delay(2500);
}

void setup()
{
  vfd.begin();
}

void loop()
{
  showMemoryScroll();
  showHorizontalWriteScroll();
  showVerticalWriteScroll();
}
