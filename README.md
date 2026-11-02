# Usage limits tray

Twee icoontjes rechtsonder in de Windows-taakbalk, één voor Claude en één voor Codex.
Het logo vult zich van onder naar boven met je verbruik in het 5-uursvenster: groen, vanaf 70% oranje en vanaf 90% rood.
Het icoon is grijs als er nog geen meting is of als de laatste meting mislukte.
Ga erover met de muis voor het verbruik in het 5-uursvenster en de week, telkens met het resettijdstip.

## Vereisten

- Windows met Windows PowerShell 5.1
- Python 3 (`py`, `python3` of `python`; het script kiest de eerste die bestaat), plus `pip install websockets` (enkel nodig voor Codex)
- Claude: aangemeld in Claude Code (leest `~/.claude/.credentials.json`)
- Codex: Codex geïnstalleerd met de app-server daemon (`~/.codex/packages/app-server-daemon`). Het script start de daemon zelf.

## Gebruik

```powershell
powershell -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File .\Tray-Limits.ps1
```

Wil je het automatisch laten starten bij aanmelden, voer dan eenmalig `.\Install-TrayStartup.ps1` uit.
Afsluiten doe je via rechtermuisklik → **Afsluiten**.

**Eenmalige manuele stap:** Windows 11 verbergt nieuwe icoontjes achter het pijltje **^** rechtsonder.
Om ze altijd te zien: **Instellingen → Persoonlijke instellingen → Taakbalk → Overige systeemvakpictogrammen**
en zet **Windows PowerShell** aan (mogelijk twee keer, één per icoon), of sleep ze vanuit het **^**-menu naar de taakbalk.

Testen zonder tray: `py -3 limits.py claude` of `py -3 limits.py codex` print de vensters als JSON.

Codex wordt elke minuut opgevraagd, Claude om de 5 minuten (anders geeft de API een 429).
Er wordt enkel verbruik gelezen; tokens worden nergens weggeschreven of getoond.
