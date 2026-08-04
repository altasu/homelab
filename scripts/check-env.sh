#!/bin/bash

# ==============================================================================
# Contrôle de format des fichiers env par service (Quadlet)
# Usage : scripts/check-env.sh <fichier.env> [<fichier.env> ...]
#
# Vérifie qu'un fichier env destiné à EnvironmentFile= (lu littéralement par
# `podman --env-file`) ne contient aucun artefact de conventions compose :
# quotes, échappement $$, placeholders ${...} ou valeurs d'exemple non
# remplacées. Ne divulgue JAMAIS les valeurs — diagnostics OK/ERREUR uniquement.
#
# Contexte : incident du 2026-08-03, ADMIN_TOKEN Argon2 détecté « en clair »
# à cause d'un échappement compose copié tel quel — voir
# docs/runbooks/quadlet-bascule-vaultwarden.md.
# ==============================================================================

set -u
STATUS=0

check_file() {
    local f="$1"
    echo "--- Contrôle : $f ---"
    if [ ! -f "$f" ]; then
        echo "❌ ERREUR : fichier introuvable"
        STATUS=1
        return
    fi

    # Permissions : 600 attendu (secrets lisibles par le seul propriétaire)
    local perms
    perms=$(stat -c "%a" "$f" 2>/dev/null || stat -f "%Lp" "$f" 2>/dev/null)
    if [ "$perms" = "600" ]; then
        echo "✅ Permissions 600"
    else
        echo "⚠️  Permissions ${perms:-inconnues} — recommandé : chmod 600 $f"
    fi

    # Lignes de valeurs uniquement : commentaires et lignes vides exclus
    # (les commentaires peuvent légitimement contenir apostrophes/quotes)
    local lines
    lines=$(grep -vE '^[[:space:]]*(#|$)' "$f")

    if echo "$lines" | grep -q "['\"]"; then
        echo "❌ ERREUR : quote dans une valeur (podman --env-file la lit littéralement)"
        STATUS=1
    else
        echo "✅ Pas de quotes"
    fi

    if echo "$lines" | grep -q '\${'; then
        echo "❌ ERREUR : placeholder \${...} non résolu (les env Quadlet contiennent des valeurs finales)"
        STATUS=1
    else
        echo "✅ Pas de placeholder \${...}"
    fi

    if echo "$lines" | grep -q '\$\$'; then
        echo "❌ ERREUR : \$\$ détecté — échappement compose à retirer (un seul \$ en Quadlet)"
        STATUS=1
    else
        echo "✅ Pas d'échappement \$\$"
    fi

    if echo "$lines" | grep -q 'your_'; then
        echo "❌ ERREUR : valeur d'exemple (your_...) non remplacée"
        STATUS=1
    else
        echo "✅ Pas de valeur d'exemple restante"
    fi

    # Le caractère # peut être interprété comme un début de commentaire par
    # l'analyseur de fichier d'environnement : la valeur serait alors
    # silencieusement tronquée (échec d'authentification difficile à diagnostiquer).
    if echo "$lines" | grep -q '#'; then
        echo "❌ ERREUR : caractère # dans une valeur — risque de troncature silencieuse, choisir une valeur sans #"
        STATUS=1
    else
        echo "✅ Pas de caractère # dans les valeurs"
    fi

    # Règles spécifiques aux variables connues
    local v
    v=$(echo "$lines" | grep '^ADMIN_TOKEN=' || true)
    if [ -n "$v" ]; then
        case "${v#ADMIN_TOKEN=}" in
            \$argon2*) echo "✅ ADMIN_TOKEN : format Argon2 PHC" ;;
            *)         echo "❌ ERREUR : ADMIN_TOKEN n'est pas au format Argon2 PHC (générer via /vaultwarden hash)"; STATUS=1 ;;
        esac
    fi

    v=$(echo "$lines" | grep '^DATABASE_URL=' || true)
    if [ -n "$v" ]; then
        case "${v#DATABASE_URL=}" in
            postgresql://*:*@*:5432/*) echo "✅ DATABASE_URL : squelette valide" ;;
            *)                         echo "❌ ERREUR : DATABASE_URL invalide (attendu : postgresql://user:motdepasse@hote:5432/base)"; STATUS=1 ;;
        esac
    fi
}

if [ $# -eq 0 ]; then
    echo "Usage : $0 <fichier.env> [<fichier.env> ...]"
    echo "Exemple : $0 ~/homelab/apps/vaultwarden.env"
    exit 2
fi

for f in "$@"; do
    check_file "$f"
done

exit $STATUS
