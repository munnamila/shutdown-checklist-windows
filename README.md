# Shutdown Checklist for Windows

A lightweight Windows shutdown checklist with a Japanese user interface. The shutdown button remains disabled until every configured item is checked.

## Features

- Japanese Windows Forms interface
- Configurable checklist stored in `checklist.json`
- Final confirmation before shutdown
- Configurable shutdown countdown
- Shutdown cancellation during the countdown
- Uses the standard Windows shutdown command without the force (`/f`) option
- No installation or third-party runtime required

## Usage

1. Download and extract `ShutdownChecklist-Windows.zip`.
2. Double-click `Start.cmd`.
3. Complete and check every item.
4. Click **シャットダウン** and confirm.

## Customization

Open `checklist.json` in a text editor:

- `items`: checklist entries
- `delay_seconds`: shutdown delay from 10 to 3600 seconds
- `title`: window title

Keep the files together in the same directory. Windows PowerShell 5.1 or later is required.

## Safety

The program calls Windows `shutdown.exe` with `/s` and `/t`, but does not use `/f`. Applications may still ask the user to save unsaved work.


