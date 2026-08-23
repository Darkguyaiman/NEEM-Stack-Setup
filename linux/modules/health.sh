# Stack inspection and concise service/application health output.
health_check() {
  clear 2>/dev/null || true
  show_brand
  local item cmd path cols max_path keep ready=0 total=9
  cols=$(tput cols 2>/dev/null || printf '100')
  max_path=$((cols - 38))
  ((max_path < 24)) && max_path=24
  for item in "Node.js:node" "npm:npm" "PM2:pm2" "MySQL:mysql" "Nginx:nginx" "Micro:micro" "Glances:glances" "Certbot:certbot" "Cloudflare:cloudflared"; do
    cmd=${item#*:}
    command -v "$cmd" >/dev/null 2>&1 && ready=$((ready + 1))
  done
  rule "STACK HEALTH"
  printf '%s  %d of %d components ready%s\n' "$CREAM" "$ready" "$total" "$RESET"
  printf '%s  %-10s %-19s %s%s\n' "$SELECTED" "STATE" "COMPONENT" "LOCATION" "$RESET"
  for item in "Node.js:node" "npm:npm" "PM2:pm2" "MySQL:mysql" "Nginx:nginx" "Micro:micro" "Glances:glances" "Certbot:certbot" "Cloudflare:cloudflared"; do
    cmd=${item#*:}
    if command -v "$cmd" >/dev/null 2>&1; then
      path=$(command -v "$cmd")
      if ((${#path} > max_path)); then
        keep=$((max_path - 3))
        path="...${path: -$keep}"
      fi
      printf '%s  %-10s %-19s %s%s\n' "$PAPER" "READY" "${item%%:*}" "$path" "$RESET"
    else
      printf '%s  %-10s %-19s %s%s\n' "$MUTED" "MISSING" "${item%%:*}" "not installed" "$RESET"
    fi
  done
  if command -v pm2 >/dev/null 2>&1; then
    printf '\n'
    rule "PM2 APPLICATIONS"
    pm2 jlist 2>/dev/null | node -e '
      let s=""; process.stdin.on("data",d=>s+=d).on("end",()=>{
        try {
          const apps=JSON.parse(s);
          if (!apps.length) return console.log("  No PM2 applications are running.");
          console.log("  ID   NAME                   STATUS        CPU     MEMORY");
          for (const app of apps) {
            const m=((app.monit?.memory||0)/1048576).toFixed(1)+" MB";
            console.log(`  ${String(app.pm_id).padEnd(4)} ${app.name.slice(0,22).padEnd(22)} ${String(app.pm2_env.status).padEnd(10)} ${String(app.monit?.cpu||0).padStart(5)}% ${m.padStart(10)}`);
          }
        } catch (_) { console.log("  PM2 process details could not be read."); }
      });'
  fi
  if command -v nginx >/dev/null 2>&1; then
    if root_run nginx -t; then ok "Nginx configuration is valid."
    else warn "Nginx configuration validation failed."
    fi
  fi
}

SELECTED_DATABASE=""
