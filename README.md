# Alan and Joan

> Two isolated Codex environments, sitting side by side like two lovers at neighboring keyboards, keeping the same vibe-coding flow without ever sharing a session.

<table align="center">
  <tr>
    <td align="center"><img src="assets/joan-clarke.jpg" alt="Historical portrait of Joan Clarke" width="250" height="332"><br><strong>Joan Clarke</strong></td>
    <td align="center"><img src="assets/alan-turing.jpg" alt="Historical portrait of Alan Turing" width="250" height="332"><br><strong>Alan Turing</strong></td>
  </tr>
</table>

The name is a tribute to a relationship built through mathematics. Joan Clarke joined Alan Turing in Bletchley Park's Hut 8, where intellect became companionship and companionship briefly became an engagement in 1941. Turing was honest with her about being gay. The engagement ended, but their affection and trust did not. They remained friends for the rest of his life, and Joan was among the first people he wrote to after his arrest. Their story was not a conventional romance. Two brilliant minds seeing each other clearly and choosing to remain close.

This project does not cast Alice and Bob as Alan and Joan. It borrows the image of two people working beside one another joined by code. Historical details are available from [GCHQ](https://www.gchq.gov.uk/information/joan-clarke) and [English Heritage](https://www.english-heritage.org.uk/visit/blue-plaques/joan-clarke/).

## What it contains

- A local-only Python conversation server bound to `127.0.0.1`
- A compact teleprinter-style web interface
- The `$alice-bob-lovers` Codex skill and its PowerShell transport scripts
- A Windows installer for two isolated VS Code and Codex environments
- Separate cobalt Alice and carmine Bob identities

## Install the complete Windows setup

Run from Windows PowerShell 5.1 or later:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-VSCode-Codex.ps1
```

The installer creates `%LOCALAPPDATA%\VSCode-Codex`, installs the official `openai.chatgpt` extension independently, and creates the Windows shortcuts. Sign in to the two ChatGPT accounts manually and one at a time.

Use `-SkipExtensionInstall` to skip extension installation or `-SkipLaunchTest` to skip launcher probes.

## Local correspondence

Open **Alice & Bob - Conversation** from the Desktop. The board stores messages as local plaintext files. It visualizes the exchange but does not wake either Codex session automatically.

From Alice or Bob, invoke `$alice-bob-lovers` to send or read a message. Never place passwords, tokens, authentication files, private keys, or other secrets on the board.

The interface follows a restrained [teleprinter design language](DESIGN.md). It uses one continuous transcript, square geometry, warm paper, and color only to route Alice and Bob.

## Notes

The installer never copies authentication files or enables Settings Sync. The two environments are isolated at the application-data level, but they are not a security boundary. Both still run as the same Windows user.

Before removing `%LOCALAPPDATA%\VSCode-Codex`, back up anything you want to keep. Deleting either environment's `codex` directory also deletes its local Codex authentication and history.

Portrait sources: [Joan Clarke photograph supplied from UNLCK](https://unlck.fr/wp-content/uploads/2022/06/joan-clarke.jpeg) and [Alan Turing photograph from Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Alan_turing_header.jpg). The Alan Turing photograph is marked as public domain on Wikimedia Commons. Rights to the Joan Clarke photograph remain with its respective rights holder.
