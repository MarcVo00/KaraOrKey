@echo off
cd /d "%~dp0"

echo ===================================================
echo     DEMARRAGE DU SERVEUR KARAORKEY
echo ===================================================

cd backend
IF NOT EXIST "venv" (
    echo [1/3] Creation de l'environnement Python - 1ere fois...
    python -m venv venv

    if errorlevel 1 (
        echo ERREUR CRITIQUE : Python n'est pas installe, ou pas dans le PATH de Windows !
        pause
        exit /b
    )

    call venv\Scripts\activate.bat
    echo Installation des outils - cela peut prendre quelques minutes...
    pip install -r requirements.txt
) ELSE (
    call venv\Scripts\activate.bat
)

echo [2/3] Demarrage du Backend Python sur le port 5000...
start "KaraorKey - Moteur Backend" cmd /k "call venv\Scripts\activate.bat && python server.py"

cd ../web
echo [3/3] Demarrage de l'application Web sur le port 8080...
start "KaraorKey - Application Web" cmd /k "python -m http.server 8080"

echo.
echo ===================================================
echo TOUT EST PRET !
echo.
echo Adresse IP de ce PC (pour les telephones) :
ipconfig | findstr /i "IPv4"
echo.
echo Sur ce PC         : http://localhost:8080
echo Sur les telephones : Lancez l'app et entrez l'IP ci-dessus
echo ===================================================
pause
