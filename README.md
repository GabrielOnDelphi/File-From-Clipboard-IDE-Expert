# File-From-Clipboard IDE Expert

File-From-Clipboard is a small Delphi IDE expert that watches the clipboard for PAS filenames (full or partial paths).  
When a filename is detected and the file exists inside a user-configured search folder, the expert opens the file in the IDE automatically.

Useful when you browse repositories on GitHub, GitLab or similar services and need to open many files quickly (for example when resolving merges).  
It also helps when working with SonarQube reports that reference source files.

## Features
- Detects PAS filenames (full or partial path) placed in the clipboard.
- Opens the file in the IDE when found.
- Simple installation

## Updates
I am just one guy with (too) many (freeware) projects.  
The projects get updates based on how many stars they get.  
Star this project if you want to see future updates and enhancements.

## Installation
This IDE expert has zero dependencies.

1. Double click the DPK file to load the package in the IDE
2. In the Project Manager, right-click the package.
3. Choose “Install”.

After installation the expert will appear in the IDE menus.

## Usage
1. Set where the expert should look for files:
   - In the IDE, open the "File From Clipboard" menu and choose Settings.
   - Add one or more folders where your project/source files live.
2. Copy a filename (full path or partial path) to the clipboard.
3. If a matching PAS file is found inside one of the configured folders, it will be opened in the IDE.

## Troubleshooting
- Nothing happens when you copy a filename?
  - Make sure the folder containing the file is added to the expert's Settings.
  - Ensure the clipboard actually contains plain text with the filename (no formatting).
  - Verify the file extension is .pas (case-insensitive).
- Multiple matches:
  - If more than one file matches a partial path, the expert may not be able to decide which to open. Use a more precise path or add folders to narrow the search.
- Permissions:
  - Ensure the IDE process has permission to read the folders you configured.

## Feedback
If you find this tool useful, please star the repository — it helps prioritize future updates.

![Screenshot](GitScreenshot.png "Title")

