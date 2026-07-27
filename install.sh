#!/usr/bin/env bash
#
# DM Chat — Installation auf einem frischen Server.
#
#   curl -fsSL https://raw.githubusercontent.com/apps-dm/DM_Chat/main/install.sh | sudo bash
#
# Richtet Web, API, Datenbank und den SFU gemeinsam auf diesem Host ein. Zwei
# Wege stehen zur Wahl:
#
#   public   — Server ist aus dem Internet erreichbar, Zertifikat per HTTP-01.
#   internal — Server ist von aussen nicht erreichbar; das Zertifikat kommt per
#              DNS-01 ueber Cloudflare, aus einer eigenen PKI oder aus Caddys
#              interner CA.
#
# Ein zweiter Aufruf aktualisiert eine bestehende Installation, statt sie zu
# ueberschreiben.
#
# Die hybride Produktivarchitektur (Pangolin-Edge plus getrennter LiveKit) ist
# hier bewusst nicht abgebildet — sie ist ein Sonderfall und bleibt
# handgefuehrt, siehe docs/operations/production-hybrid.md.

set -euo pipefail

readonly APP_IMAGE_REPO='ghcr.io/apps-dm/dm-chat'
readonly CADDY_IMAGE_REPO='ghcr.io/apps-dm/dm-chat-caddy'
readonly TEMPLATE_PATH='/opt/dm-chat/deploy-template'
readonly MIN_RAM_MB=1800
readonly MIN_DISK_GB=15

INSTALL_DIR='/opt/dm-chat'
MODE=''
# Nicht VERSION nennen: /etc/os-release setzt genau diesen Namen, und ein
# Sourcen davon wuerde den Wert stillschweigend durch die Betriebssystem-
# version ersetzen — --version waere wirkungslos und der Standardfall zoege
# einen Tag wie "12 (bookworm)".
IMAGE_VERSION='latest'
DRY_RUN=0
ASSUME_YES=0

# --------------------------------------------------------------------------
# Ausgabe
# --------------------------------------------------------------------------

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
	C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
	C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BLUE=$'\033[36m'
else
	C_RESET=''; C_BOLD=''; C_DIM=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''
fi

step()  { printf '\n%s==>%s %s%s%s\n' "$C_BLUE" "$C_RESET" "$C_BOLD" "$1" "$C_RESET"; }
info()  { printf '    %s\n' "$1"; }
good()  { printf '    %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$1"; }
warn()  { printf '    %s!%s %s\n' "$C_YELLOW" "$C_RESET" "$1" >&2; }
die()   { printf '\n%sAbbruch:%s %s\n\n' "$C_RED" "$C_RESET" "$1" >&2; exit 1; }

# --------------------------------------------------------------------------
# Eingabe
#
# Beim Aufruf ueber `curl | bash` ist die Standardeingabe das Skript selbst —
# ein schlichtes `read` bekaeme dessen Rest als Antwort. Alle Abfragen lesen
# deshalb ausdruecklich vom Terminal.
# --------------------------------------------------------------------------

TTY='/dev/tty'

# Nicht mit `[ -r /dev/tty ]` pruefen: die Datei existiert auch dann, wenn der
# Prozess gar kein steuerndes Terminal hat (etwa unter `docker exec` ohne -t,
# in cloud-init oder Ansible). Der Test muss das Oeffnen wirklich versuchen,
# sonst scheitert erst das spaetere read — mit roher Bash-Fehlermeldung und
# einer Vorgabeantwort, die niemand gegeben hat.
require_tty() {
	if ! { : <"$TTY"; } 2>/dev/null; then
		die "Keine Terminaleingabe verfuegbar (kein steuerndes Terminal).
    Bei 'curl | sudo bash' passiert das, wenn die Sitzung selbst kein Terminal
    hat. Dann das Skript erst herunterladen und dann starten:
      curl -fsSL <url> -o install.sh && sudo bash install.sh
    Ganz ohne Rueckfragen laeuft nur --dry-run."
	fi
}

ask() { # ask <Frage> <Vorgabe> -> Antwort auf stdout
	local prompt="$1" default="${2:-}" answer=''
	require_tty
	if [ -n "$default" ]; then
		printf '    %s %s[%s]%s ' "$prompt" "$C_DIM" "$default" "$C_RESET" >/dev/tty
	else
		printf '    %s ' "$prompt" >/dev/tty
	fi
	IFS= read -r answer <"$TTY" || answer=''
	printf '%s' "${answer:-$default}"
}

ask_required() { # bricht nicht ab, sondern fragt erneut
	local answer=''
	while :; do
		answer="$(ask "$1" "${2:-}")"
		[ -n "$answer" ] && { printf '%s' "$answer"; return; }
		warn 'Bitte einen Wert eingeben.'
	done
}

ask_secret() { # ohne Bildschirmecho
	local prompt="$1" answer=''
	require_tty
	printf '    %s ' "$prompt" >/dev/tty
	IFS= read -rs answer <"$TTY" || answer=''
	printf '\n' >/dev/tty
	printf '%s' "$answer"
}

confirm() { # confirm <Frage> <j|n>
	local prompt="$1" default="${2:-n}" answer=''
	[ "$ASSUME_YES" = 1 ] && return 0
	require_tty
	local hint='j/N'
	[ "$default" = 'j' ] && hint='J/n'
	printf '    %s %s[%s]%s ' "$prompt" "$C_DIM" "$hint" "$C_RESET" >/dev/tty
	IFS= read -r answer <"$TTY" || answer=''
	answer="${answer:-$default}"
	case "$answer" in [jJyY]*) return 0 ;; *) return 1 ;; esac
}

pause_for_enter() {
	require_tty
	printf '    %s' "$1" >/dev/tty
	IFS= read -r _ <"$TTY" || true
}

# --------------------------------------------------------------------------
# Argumente
# --------------------------------------------------------------------------

usage() {
	cat <<'EOF'
DM Chat — Installation

  install.sh [Optionen]

  --mode public|internal   Weg vorgeben statt danach zu fragen
  --version <tag>          Image-Version (Vorgabe: latest)
  --dir <pfad>             Zielverzeichnis (Vorgabe: /opt/dm-chat)
  --dry-run                Nur pruefen und zeigen, was geschehen wuerde
  --yes                    Rueckfragen mit Ja beantworten
  --help                   Diese Hilfe

Ein erneuter Aufruf in einem vorhandenen Zielverzeichnis aktualisiert die
Installation, statt die Konfiguration zu ueberschreiben.
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
		--mode) MODE="${2:-}"; shift 2 ;;
		--mode=*) MODE="${1#*=}"; shift ;;
		--version) IMAGE_VERSION="${2:-}"; shift 2 ;;
		--version=*) IMAGE_VERSION="${1#*=}"; shift ;;
		--dir) INSTALL_DIR="${2:-}"; shift 2 ;;
		--dir=*) INSTALL_DIR="${1#*=}"; shift ;;
		--dry-run) DRY_RUN=1; shift ;;
		--yes|-y) ASSUME_YES=1; shift ;;
		--help|-h) usage; exit 0 ;;
		*) die "Unbekannte Option: $1 (--help zeigt alle)" ;;
	esac
done

case "$MODE" in
	''|public|internal) ;;
	*) die "--mode akzeptiert nur 'public' oder 'internal', nicht '$MODE'." ;;
esac

DEPLOY_DIR="$INSTALL_DIR/deploy"

# --------------------------------------------------------------------------
# Vorbedingungen
# --------------------------------------------------------------------------

preflight() {
	step 'Systemvoraussetzungen'

	[ "$(id -u)" = 0 ] || die 'Bitte als root ausfuehren (oder mit sudo).'

	[ -r /etc/os-release ] || die 'Nicht unterstuetztes System: /etc/os-release fehlt.'
	# In einer Subshell auslesen statt in den Skript-Namensraum sourcen:
	# os-release setzt unter anderem NAME und VERSION und wuerde gleichnamige
	# Variablen des Skripts ueberschreiben.
	local os_family os_pretty
	# shellcheck disable=SC1091
	os_family="$( . /etc/os-release 2>/dev/null; printf '%s' "${ID:-}${ID_LIKE:-}" )"
	# shellcheck disable=SC1091
	os_pretty="$( . /etc/os-release 2>/dev/null; printf '%s' "${PRETTY_NAME:-${ID:-unbekannt}}" )"
	case "$os_family" in
		*debian*|*ubuntu*) good "System: $os_pretty" ;;
		*) warn "Getestet ist Debian/Ubuntu, hier laeuft $os_pretty."
		   confirm 'Trotzdem fortfahren?' n || die 'Auf Wunsch beendet.' ;;
	esac

	local arch; arch="$(uname -m)"
	if [ "$arch" != 'x86_64' ]; then
		warn "Die veroeffentlichten Images sind fuer x86_64 gebaut, dieser Host ist $arch."
		confirm 'Trotzdem fortfahren?' n || die 'Auf Wunsch beendet.'
	else
		good "Architektur: $arch"
	fi

	local ram_mb; ram_mb=$(( $(awk '/MemTotal/ {print $2}' /proc/meminfo) / 1024 ))
	if [ "$ram_mb" -lt "$MIN_RAM_MB" ]; then
		warn "Nur ${ram_mb} MB Arbeitsspeicher; empfohlen sind mindestens ${MIN_RAM_MB} MB."
		confirm 'Trotzdem fortfahren?' n || die 'Auf Wunsch beendet.'
	else
		good "Arbeitsspeicher: ${ram_mb} MB"
	fi

	local disk_kb disk_gb
	disk_kb="$(df -Pk /var/lib 2>/dev/null | awk 'NR==2 {print $4}' || true)"
	disk_gb=$(( ${disk_kb:-0} / 1024 / 1024 ))
	if [ -z "$disk_kb" ]; then
		warn 'Freier Speicher liess sich nicht ermitteln — bitte selbst pruefen.'
	elif [ "$disk_gb" -lt "$MIN_DISK_GB" ]; then
		warn "Nur ${disk_gb} GB frei unter /var/lib; empfohlen sind ${MIN_DISK_GB} GB."
		confirm 'Trotzdem fortfahren?' n || die 'Auf Wunsch beendet.'
	else
		good "Freier Speicher: ${disk_gb} GB"
	fi
}

ensure_docker() {
	step 'Docker'
	if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
		good "Vorhanden: $(docker --version | cut -d, -f1)"
		return
	fi
	if [ "$DRY_RUN" = 1 ]; then
		info 'Docker fehlt und wuerde ueber get.docker.com installiert.'
		return
	fi
	warn 'Docker mit Compose-Plugin fehlt.'
	confirm 'Jetzt ueber das offizielle Skript von get.docker.com installieren?' j \
		|| die 'Ohne Docker geht es nicht weiter.'
	curl -fsSL https://get.docker.com | sh
	docker compose version >/dev/null 2>&1 || die 'Docker wurde installiert, das Compose-Plugin fehlt aber weiterhin.'
	systemctl enable --now docker >/dev/null 2>&1 || true
	good 'Docker installiert.'
}

check_ports() {
	command -v ss >/dev/null 2>&1 || return 0
	local busy='' p
	for p in 80 443 3478; do
		if ss -lnt "sport = :$p" 2>/dev/null | grep -q LISTEN; then busy="$busy $p"; fi
	done
	if [ -n "$busy" ]; then
		warn "Diese Ports sind bereits belegt:$busy"
		info 'Laeuft dort ein anderer Webserver, kann DM Chat nicht starten.'
		confirm 'Trotzdem fortfahren?' n || die 'Auf Wunsch beendet.'
	fi
}

# --------------------------------------------------------------------------
# Befragung
# --------------------------------------------------------------------------

choose_mode() {
	[ -n "$MODE" ] && return
	step 'Wie ist dieser Server erreichbar?'
	cat <<EOF

    ${C_BOLD}1) public${C_RESET}   — aus dem Internet erreichbar
                 Zertifikat holt sich Caddy selbst (HTTP-01).
                 Braucht einen DNS-Eintrag auf diesen Server und offene
                 Ports 80 und 443.

    ${C_BOLD}2) internal${C_RESET} — nur im eigenen Netz erreichbar
                 Zertifikat per DNS-01 ueber Cloudflare, aus eigener PKI
                 oder aus Caddys interner CA.

EOF
	local choice; choice="$(ask 'Auswahl (1/2):' '1')"
	case "$choice" in
		1|public) MODE='public' ;;
		2|internal) MODE='internal' ;;
		*) die "Ungueltige Auswahl: $choice" ;;
	esac
	good "Weg: $MODE"
}

# Erste nicht-lokale IPv4 dieses Hosts — als Vorschlag, nicht als Wahrheit.
guess_lan_ip() {
	ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") {print $(i+1); exit}}'
}

check_dns_points_here() { # nur beratend; ein Fehlschlag bricht nichts ab
	local host="$1" resolved public
	command -v getent >/dev/null 2>&1 || return 0
	# `|| true` ist hier Pflicht, nicht Bequemlichkeit: getent liefert bei einer
	# unbekannten Domain Exit 2, und zusammen mit `set -e` samt pipefail wuerde
	# das Skript an dieser Stelle wortlos sterben — ausgerechnet im haeufigsten
	# Fall einer Neuinstallation, in dem der DNS-Eintrag noch fehlt.
	resolved="$(getent ahostsv4 "$host" 2>/dev/null | awk 'NR==1 {print $1}' || true)"
	if [ -z "$resolved" ]; then
		warn "$host loest derzeit nicht auf. Ohne DNS-Eintrag scheitert die Zertifikatsausstellung."
		confirm 'Trotzdem fortfahren?' n || die 'Auf Wunsch beendet.'
		return
	fi
	public="$(curl -fsS --max-time 8 https://api.ipify.org 2>/dev/null || true)"
	if [ -z "$public" ]; then
		info "$host zeigt auf $resolved (eigene oeffentliche IP nicht ermittelbar)."
		return
	fi
	if [ "$resolved" = "$public" ]; then
		good "$host zeigt auf diesen Server ($public)."
	else
		warn "$host zeigt auf $resolved, dieser Server ist aber unter $public erreichbar."
		info 'Solange das nicht zusammenpasst, wird Let'"'"'s Encrypt kein Zertifikat ausstellen.'
		confirm 'Trotzdem fortfahren?' n || die 'Auf Wunsch beendet.'
	fi
}

TLS_KIND=''
collect_answers() {
	step 'Adresse dieser Installation'
	APP_HOST="$(ask_required 'Domain (z.B. chat.example.com):')"
	info "Daraus ergibt sich https://$APP_HOST"

	if [ "$MODE" = 'public' ]; then
		check_dns_points_here "$APP_HOST"
		TLS_KIND='acme-http'
		ACME_EMAIL="$(ask_required 'E-Mail fuer Zertifikatswarnungen:')"
		LIVEKIT_NODE_IP=''
		LIVEKIT_USE_EXTERNAL_IP='true'
	else
		step 'Zertifikat'
		cat <<EOF

    ${C_BOLD}1) Cloudflare (DNS-01)${C_RESET} — empfohlen
          Oeffentlich gueltiges Zertifikat ohne offene Ports. Braucht einen
          API-Token mit Zone:Read und DNS:Edit.

    ${C_BOLD}2) Eigenes Zertifikat${C_RESET}
          Vorhandene fullchain.pem und privkey.pem. Erneuerung bleibt bei dir.

    ${C_BOLD}3) Caddys interne CA${C_RESET} — letzte Wahl
          Ohne Internet und ohne DNS-Token, aber das Wurzelzertifikat muss
          auf JEDEM Geraet installiert werden. Ohne das verweigern die
          Desktop- und die iOS-App die Verbindung.

EOF
		local choice; choice="$(ask 'Auswahl (1/2/3):' '1')"
		case "$choice" in
			1) TLS_KIND='acme-dns'
			   CLOUDFLARE_API_TOKEN="$(ask_secret 'Cloudflare-API-Token (Eingabe bleibt unsichtbar):')"
			   [ -n "$CLOUDFLARE_API_TOKEN" ] || die 'Ohne Token kann die DNS-Challenge nicht laufen.' ;;
			2) TLS_KIND='own-cert' ;;
			3) TLS_KIND='internal-ca'
			   warn 'Das Wurzelzertifikat muss danach auf alle Geraete verteilt werden.' ;;
			*) die "Ungueltige Auswahl: $choice" ;;
		esac

		step 'Medienadresse'
		info 'Diese IP sagt der SFU den Clients fuer Voice und Screenshare an.'
		LIVEKIT_NODE_IP="$(ask_required 'LAN-IP dieses Servers:' "$(guess_lan_ip)")"
		LIVEKIT_USE_EXTERNAL_IP='false'
	fi

	step 'Optionales'
	RESEND_API_KEY=''
	PASSWORD_RESET_ENABLED='false'
	EMAIL_FROM="DM Chat <noreply@$APP_HOST>"
	if confirm 'Passwort-Reset per E-Mail einrichten (braucht einen Resend-Key)?' n; then
		RESEND_API_KEY="$(ask_secret 'Resend-API-Key:')"
		if [ -n "$RESEND_API_KEY" ]; then
			PASSWORD_RESET_ENABLED='true'
			EMAIL_FROM="$(ask 'Absender:' "$EMAIL_FROM")"
		else
			warn 'Kein Key eingegeben — Passwort-Reset bleibt aus.'
		fi
	fi
}

# --------------------------------------------------------------------------
# Erzeugen und Schreiben
# --------------------------------------------------------------------------

# Bewusst hexadezimal: diese Werte landen in einer Postgres-URL und in einer
# YAML-Zeile. Ein '/' oder '$' aus base64 wuerde die URL zerlegen oder von
# Compose als Variable gelesen.
rand_hex() { openssl rand -hex "$1"; }

generate_secrets() {
	step 'Zugangsdaten erzeugen'
	command -v openssl >/dev/null 2>&1 || die 'openssl fehlt und wird zum Erzeugen der Zugangsdaten gebraucht.'
	POSTGRES_PASSWORD="$(rand_hex 24)"
	LIVEKIT_API_KEY="API$(rand_hex 8)"
	LIVEKIT_API_SECRET="$(rand_hex 32)"
	good 'Datenbankpasswort und LiveKit-Schluessel erzeugt (werden nicht angezeigt).'
}

resolve_image() { # gibt eine auf den Digest festgenagelte Referenz zurueck
	local ref="$1:$2" digest=''
	docker pull --quiet "$ref" >/dev/null
	digest="$(docker image inspect --format '{{if .RepoDigests}}{{index .RepoDigests 0}}{{end}}' "$ref" 2>/dev/null || true)"
	if [ -n "$digest" ]; then printf '%s' "$digest"; else printf '%s' "$ref"; fi
}

fetch_template() {
	step 'Deploy-Vorlage aus dem Image holen'
	local cid
	cid="$(docker create "$APP_IMAGE_PINNED")"
	mkdir -p "$DEPLOY_DIR"
	docker cp "$cid:$TEMPLATE_PATH/." "$DEPLOY_DIR/"
	docker rm -v "$cid" >/dev/null
	[ -f "$DEPLOY_DIR/compose/standalone.yml" ] \
		|| die "Die Vorlage fehlt im Image. Passt --version=$IMAGE_VERSION zu einem Build, das sie schon enthaelt?"
	mkdir -p "$DEPLOY_DIR/backups"
	good "Vorlage liegt in $DEPLOY_DIR"
}

write_tls_snippet() {
	local target="$DEPLOY_DIR/tls/active.caddy"
	mkdir -p "$DEPLOY_DIR/tls"
	case "$TLS_KIND" in
		acme-http)   printf 'tls %s\n' "$ACME_EMAIL" > "$target" ;;
		# propagation_timeout -1 ist hier kein Feinschliff, sondern noetig:
		# Caddy pruefe sonst ueber den Resolver des Servers, ob sein eigener
		# TXT-Eintrag aufloesbar ist. Interne Netze haben fast immer einen
		# cachenden Resolver, der das "gibt es nicht" des ersten Versuchs
		# 30 Minuten lang festhaelt (SOA-Minimum der Zone) — Caddy sieht den
		# Eintrag dann nie und dreht sich endlos im Kreis. Let's Encrypt
		# fragt von aussen und ist davon nicht betroffen; statt der Pruefung
		# wird eine feste Zeit abgewartet. Begruendung in
		# deploy/tls/dns-cloudflare.caddy.example.
		acme-dns)    printf 'tls {\n\tdns cloudflare {env.CLOUDFLARE_API_TOKEN}\n\tpropagation_delay 60s\n\tpropagation_timeout -1\n}\n' > "$target" ;;
		own-cert)    printf 'tls /etc/caddy/tls/fullchain.pem /etc/caddy/tls/privkey.pem\n' > "$target" ;;
		internal-ca) printf 'tls internal\n' > "$target" ;;
		*) die "Unbekannte Zertifikatsart: $TLS_KIND" ;;
	esac
}

write_env() {
	step 'Konfiguration schreiben'
	local env_file="$DEPLOY_DIR/.env"
	local old_umask; old_umask="$(umask)"
	umask 077
	cat > "$env_file" <<EOF
# Von deploy/install.sh erzeugt. Enthaelt Zugangsdaten — nicht weitergeben.
# Weg: $MODE

COMPOSE_FILE=docker-compose.yml:compose/standalone.yml

# Auf den Digest festgenagelt: ein Neustart aktualisiert dadurch nicht
# ungeplant. Ein Update ist eine bewusste Aenderung dieser beiden Zeilen —
# oder ein erneuter Aufruf von install.sh.
APP_IMAGE=$APP_IMAGE_PINNED
CADDY_IMAGE=$CADDY_IMAGE_PINNED

APP_HOST=$APP_HOST
APP_ORIGIN=https://$APP_HOST
LIVEKIT_WS_URL=wss://$APP_HOST

LIVEKIT_NODE_IP=$LIVEKIT_NODE_IP
LIVEKIT_USE_EXTERNAL_IP=$LIVEKIT_USE_EXTERNAL_IP
CLOUDFLARE_API_TOKEN=${CLOUDFLARE_API_TOKEN:-}
TRUSTED_PROXY_CIDR=127.0.0.1/32

LIVEKIT_API_KEY=$LIVEKIT_API_KEY
LIVEKIT_API_SECRET=$LIVEKIT_API_SECRET
POSTGRES_PASSWORD=$POSTGRES_PASSWORD

RESEND_API_KEY=$RESEND_API_KEY
PASSWORD_RESET_ENABLED=$PASSWORD_RESET_ENABLED
EMAIL_FROM=$EMAIL_FROM

WEBHOOK_PRIVATE_HOST_ALLOWLIST=
EOF
	umask "$old_umask"
	chmod 600 "$env_file"
	write_tls_snippet
	good "$env_file geschrieben (nur fuer root lesbar)"
}

# LiveKit warnt sonst bei jedem Start, dass der UDP-Empfangspuffer zu klein
# ist; unter Last aeussert sich das als stockendes Audio.
tune_udp_buffers() {
	step 'Kernel-Puffer fuer WebRTC'
	local conf='/etc/sysctl.d/99-dm-chat.conf'
	cat > "$conf" <<'EOF'
# DM Chat: LiveKit braucht groessere UDP-Puffer als die Voreinstellung.
net.core.rmem_max = 5000000
net.core.wmem_max = 5000000
EOF
	sysctl -p "$conf" >/dev/null 2>&1 || warn 'Werte konnten nicht sofort gesetzt werden; nach einem Neustart greifen sie.'
	good 'UDP-Puffer erhoeht.'
}

# --------------------------------------------------------------------------
# Start
# --------------------------------------------------------------------------

compose() { (cd "$DEPLOY_DIR" && docker compose "$@"); }

start_stack() {
	step 'Dienste starten'
	compose pull --quiet 2>/dev/null || compose pull
	compose up -d
	good 'Container gestartet.'
}

wait_for_health() {
	step 'Auf die Anwendung warten'
	local i status=''
	for i in $(seq 1 60); do
		status="$(curl -fsS --max-time 3 http://127.0.0.1:3000/api/health 2>/dev/null || true)"
		case "$status" in
			*'"status":"ok"'*) good "Anwendung antwortet (nach ${i}0 Sekunden nicht laenger als noetig gewartet)."; return 0 ;;
		esac
		sleep 2
	done
	warn 'Die Anwendung hat innerhalb von zwei Minuten nicht geantwortet.'
	info 'Die letzten Zeilen aus dem Anwendungslog:'
	compose logs --tail 25 app || true
	die 'Start fehlgeschlagen. Nach dem Beheben genuegt: cd '"$DEPLOY_DIR"' && docker compose up -d'
}

configure_firewall() {
	command -v ufw >/dev/null 2>&1 || { info 'ufw ist nicht installiert — bitte die Ports von Hand freigeben (siehe Zusammenfassung).'; return; }
	step 'Firewall'
	info 'LiveKit laeuft im Netzwerk-Namespace des Hosts. Docker oeffnet die'
	info 'Medienports dadurch NICHT automatisch an der Firewall vorbei — ohne'
	info 'Freigaben funktionieren Chat und Web, aber Voice bleibt stumm.'
	confirm 'Die noetigen ufw-Regeln jetzt setzen?' j || { warn 'Uebersprungen — die Regeln stehen in der Zusammenfassung.'; return; }
	# Zuerst SSH, sonst sperrt ein spaeteres `ufw enable` die Sitzung aus.
	ufw allow OpenSSH >/dev/null 2>&1 || ufw allow 22/tcp >/dev/null 2>&1 || true
	ufw allow 80,443/tcp >/dev/null
	ufw allow 443/udp >/dev/null
	ufw allow 7881/tcp >/dev/null
	ufw allow 7882/udp >/dev/null
	ufw allow 3478/udp >/dev/null
	ufw allow 30000:30099/udp >/dev/null
	ufw deny 7880/tcp >/dev/null
	good 'Regeln gesetzt (SSH ausdruecklich zuerst).'
	if ! ufw status 2>/dev/null | grep -q '^Status: active'; then
		warn 'ufw ist derzeit nicht aktiv; die Regeln greifen erst nach: ufw enable'
	fi
}

bootstrap_admin() {
	step 'Erstes Konto'
	local code
	# Auch hier `|| true`: schlaegt der Aufruf fehl, soll die Meldung unten
	# greifen statt der Installer kurz vor dem Ziel abzubrechen.
	code="$(compose exec -T app node dist/scripts/create-invite.js 2>/dev/null | sed -n 's/^Invite-Code: //p' | tr -d '\r' || true)"
	if [ -z "$code" ]; then
		warn 'Der Invite-Code konnte nicht erzeugt werden.'
		info "Von Hand: cd $DEPLOY_DIR && docker compose exec app node dist/scripts/create-invite.js"
		return
	fi
	cat <<EOF

    Die Anwendung laeuft. Zum Anlegen des ersten Kontos:

      1. ${C_BOLD}https://$APP_HOST${C_RESET} oeffnen
      2. Registrieren mit dem Invite-Code: ${C_BOLD}$code${C_RESET}

EOF
	pause_for_enter 'Danach hier die Eingabetaste druecken … '
	local email
	email="$(ask 'E-Mail des gerade angelegten Kontos (leer = spaeter):' '')"
	if [ -z "$email" ]; then
		warn 'Uebersprungen. Nachtraeglich:'
		info "cd $DEPLOY_DIR && docker compose exec app node dist/scripts/promote-platform-admin.js <email> --confirm"
		return
	fi
	if compose exec -T app node dist/scripts/promote-platform-admin.js "$email" --confirm; then
		good "$email ist jetzt Platform-Admin."
	else
		warn 'Das Konto wurde nicht gefunden — wurde die Registrierung wirklich abgeschlossen?'
		info "Nachtraeglich: cd $DEPLOY_DIR && docker compose exec app node dist/scripts/promote-platform-admin.js <email> --confirm"
	fi
}

summary() {
	step 'Fertig'
	cat <<EOF

    ${C_BOLD}DM Chat laeuft:  https://$APP_HOST${C_RESET}

    Verzeichnis      $DEPLOY_DIR
    Weg              $MODE
    Zugangsdaten     $DEPLOY_DIR/.env  (nur root, enthaelt Secrets)
    Sicherungen      $DEPLOY_DIR/backups  (taeglich gegen 03:00, 14 Tage)

    Laufenden Betrieb ansehen
      cd $DEPLOY_DIR && docker compose ps
      cd $DEPLOY_DIR && docker compose logs -f app

    Aktualisieren
      install.sh erneut aufrufen

    Ports, die erreichbar sein muessen
      80,443/tcp und 443/udp    Web, API, WebSocket
      7882/udp, 7881/tcp        Medien fuer Voice und Screenshare
      3478/udp, 30000-30099/udp TURN-Relay fuer Clients hinter CGNAT
      7880/tcp                  ${C_BOLD}nicht${C_RESET} oeffnen — nur intern fuer Caddy

EOF
	case "$TLS_KIND" in
		own-cert)
			warn 'Noch zu tun: fullchain.pem und privkey.pem nach '"$DEPLOY_DIR/tls/"' legen,'
			info 'danach: cd '"$DEPLOY_DIR"' && docker compose restart caddy' ;;
		internal-ca)
			warn 'Noch zu tun: das Wurzelzertifikat auf alle Geraete verteilen, sonst'
			info 'verweigern Browser und Apps die Verbindung. Herausholen mit:'
			info "cd $DEPLOY_DIR && docker compose cp caddy:/data/caddy/pki/authorities/local/root.crt ." ;;
	esac
	printf '\n'
}

# --------------------------------------------------------------------------
# Aktualisieren statt neu einrichten
# --------------------------------------------------------------------------

update_existing() {
	step 'Vorhandene Installation gefunden'
	info "$DEPLOY_DIR/.env existiert bereits — es wird aktualisiert, nicht neu eingerichtet."
	if [ "$DRY_RUN" = 1 ]; then
		info 'Ein echter Lauf wuerde die Images neu festnageln und die Dienste neu starten.'
		exit 0
	fi
	confirm 'Auf die neueste Version aktualisieren?' j || die 'Auf Wunsch beendet.'

	local ts; ts="$(date +%Y%m%d-%H%M%S)"
	cp -a "$DEPLOY_DIR/.env" "$DEPLOY_DIR/.env.bak-$ts"
	good "Bisherige Konfiguration gesichert als .env.bak-$ts"

	local app_pinned caddy_pinned
	app_pinned="$(resolve_image "$APP_IMAGE_REPO" "$IMAGE_VERSION")"
	caddy_pinned="$(resolve_image "$CADDY_IMAGE_REPO" 'latest')"
	# Nur die beiden Image-Zeilen ersetzen, alles andere unangetastet lassen.
	sed -i "s#^APP_IMAGE=.*#APP_IMAGE=$app_pinned#; s#^CADDY_IMAGE=.*#CADDY_IMAGE=$caddy_pinned#" "$DEPLOY_DIR/.env"

	# Die Vorlage im Image kann neue Compose-Dateien mitbringen; die eigene
	# .env und das TLS-Schnipsel bleiben davon unberuehrt.
	local cid; cid="$(docker create "$app_pinned")"
	docker cp "$cid:$TEMPLATE_PATH/compose/." "$DEPLOY_DIR/compose/"
	docker cp "$cid:$TEMPLATE_PATH/Caddyfile.standalone" "$DEPLOY_DIR/Caddyfile.standalone"
	docker rm -v "$cid" >/dev/null

	compose pull
	compose up -d
	APP_HOST="$(sed -n 's/^APP_HOST=//p' "$DEPLOY_DIR/.env" | head -1)"
	wait_for_health
	step 'Fertig'
	info "DM Chat wurde aktualisiert: https://$APP_HOST"
	printf '\n'
	exit 0
}

# --------------------------------------------------------------------------

main() {
	printf '\n%s  DM Chat — Installation%s\n' "$C_BOLD" "$C_RESET"

	preflight
	[ -f "$DEPLOY_DIR/.env" ] && update_existing

	choose_mode
	collect_answers
	check_ports

	if [ "$DRY_RUN" = 1 ]; then
		step 'Probelauf'
		info "Weg:             $MODE"
		info "Domain:          $APP_HOST"
		info "Zertifikat:      $TLS_KIND"
		info "Zielverzeichnis: $DEPLOY_DIR"
		info "Images:          $APP_IMAGE_REPO:$IMAGE_VERSION und $CADDY_IMAGE_REPO:latest"
		info 'Es wurde nichts veraendert.'
		printf '\n'
		exit 0
	fi

	ensure_docker
	generate_secrets

	step 'Images holen'
	APP_IMAGE_PINNED="$(resolve_image "$APP_IMAGE_REPO" "$IMAGE_VERSION")"
	good "Anwendung: $APP_IMAGE_PINNED"
	CADDY_IMAGE_PINNED="$(resolve_image "$CADDY_IMAGE_REPO" 'latest')"
	good "Caddy:     $CADDY_IMAGE_PINNED"

	fetch_template
	write_env
	tune_udp_buffers
	start_stack
	wait_for_health
	configure_firewall
	bootstrap_admin
	summary
}

# Bewusst kein BASH_SOURCE-Vergleich: beim Aufruf ueber `curl | bash` kommt das
# Skript von der Standardeingabe, und ein solcher Test wuerde dort nicht
# zuverlaessig greifen — der Installer taete dann schlicht nichts. Nur ein
# ausdruecklich gesetzter Schalter unterdrueckt den Start, damit Tests einzelne
# Funktionen aufrufen koennen.
[ -n "${DM_INSTALL_LIB_ONLY:-}" ] || main
