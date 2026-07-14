@echo off
timeout /t 30 /nobreak
wsl -u YOURUSERNAMEHERE -e sh -c "cd /home/YOURUSERNAMEHERE/projects/smokeping-monitoring && docker compose up -d"
