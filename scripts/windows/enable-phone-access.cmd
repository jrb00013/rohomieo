@echo off
:: Right-click this file -> Run as administrator
setlocal
for /f "tokens=1" %%i in ('wsl -e hostname -I') do set WSL_IP=%%i
echo WSL IP: %WSL_IP%
netsh interface portproxy delete v4tov4 listenport=8443 listenaddress=0.0.0.0 >nul 2>&1
netsh interface portproxy add v4tov4 listenport=8443 listenaddress=0.0.0.0 connectport=8443 connectaddress=%WSL_IP%
echo.
netsh interface portproxy show all
netsh advfirewall firewall add rule name="Rohomieo-Signaling-TCP" dir=in action=allow protocol=TCP localport=8443 >nul 2>&1
echo.
echo Open on your phone:  https://192.168.1.223:8443
echo Accept the certificate warning.
echo.
pause
