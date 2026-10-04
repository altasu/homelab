#!/usr/bin/env bash
# ==============================================================================
# scripts/check-glance.sh — Contrôle de conformité et garde-fou du tableau de bord Glance
#
# Usage :
#   scripts/check-glance.sh [<chemin/glance.yml>] [<chemin/fichier.env>] [--runtime]
#
# Exemples :
#   CI/CD (mode statique)  : scripts/check-glance.sh apps/glance/glance.yml apps/glance.env.example
#   Serveur (mode runtime) : scripts/check-glance.sh apps/glance/glance.yml apps/glance.env --runtime
#
# Objectifs :
#   1. Valider la syntaxe et la structure YAML (interdiction stricte des tabulations).
#   2. Garantir la parité des variables d'environnement (${VAR} vs fichier .env).
#   3. Vérifier la conformité stricte des icônes (strictement préfixes 'si:' ou 'mdi:').
#   4. Empêcher les pannes et régressions lors de l'ajout de nouveaux services.
# ==============================================================================

set -euo pipefail

STATUS=0
RUNTIME_MODE=0

# Arguments
GLANCE_FILE=""
ENV_FILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --runtime)
            RUNTIME_MODE=1
            shift
            ;;
        -*)
            echo "⚠️ Option inconnue : $1"
            shift
            ;;
        *)
            if [ -z "${GLANCE_FILE}" ]; then
                GLANCE_FILE="$1"
            elif [ -z "${ENV_FILE}" ]; then
                ENV_FILE="$1"
            else
                echo "⚠️ Paramètre supplémentaire ignoré : $1"
            fi
            shift
            ;;
    esac
done

GLANCE_FILE="${GLANCE_FILE:-apps/glance/glance.yml}"
ENV_FILE="${ENV_FILE:-apps/glance.env.example}"

echo "=============================================================================="
echo "🔍 Vérification de conformité Glance : ${GLANCE_FILE} (Env: ${ENV_FILE})"
if [ "${RUNTIME_MODE}" -eq 1 ]; then
    echo "⚡ Mode d'exécution : RUNTIME (vérification stricte des valeurs de production)"
else
    echo "📋 Mode d'exécution : STATIQUE / CI (vérification de déclaration et parité)"
fi
echo "=============================================================================="

# 1. Vérification de l'existence des fichiers
if [ ! -f "${GLANCE_FILE}" ]; then
    echo "❌ ERREUR : Fichier de configuration Glance introuvable : ${GLANCE_FILE}"
    exit 1
fi

if [ ! -f "${ENV_FILE}" ]; then
    echo "❌ ERREUR : Fichier d'environnement introuvable : ${ENV_FILE}"
    exit 1
fi

# 2. Contrôle de syntaxe YAML & Structure
echo "--- Étape 1 : Validation syntaxique YAML ---"

# Vérification stricte de l'absence de tabulations (interdites dans la spécification YAML)
if grep -q "$(printf '\t')" "${GLANCE_FILE}"; then
    echo "❌ ERREUR : Tabulation(s) détectée(s) dans ${GLANCE_FILE} (YAML requiert des espaces) !"
    STATUS=1
else
    echo "✅ Aucune tabulation illégale détectée (indentation conforme)."
fi

# Validation par analyseur YAML si disponible dans l'environnement
YAML_VALIDATOR_FOUND=0
if command -v ruby >/dev/null 2>&1; then
    if ruby -e "require 'yaml'; YAML.load_file('${GLANCE_FILE}')" >/dev/null 2>&1; then
        echo "✅ Syntaxe YAML validée avec succès (Ruby YAML parser)."
        YAML_VALIDATOR_FOUND=1
    else
        echo "❌ ERREUR : Échec de validation syntaxique YAML (Ruby YAML parser) !"
        STATUS=1
        YAML_VALIDATOR_FOUND=1
    fi
elif command -v python3 >/dev/null 2>&1 && python3 -c "import yaml" >/dev/null 2>&1; then
    if python3 -c "import yaml; yaml.safe_load(open('${GLANCE_FILE}'))" >/dev/null 2>&1; then
        echo "✅ Syntaxe YAML validée avec succès (Python PyYAML parser)."
        YAML_VALIDATOR_FOUND=1
    else
        echo "❌ ERREUR : Échec de validation syntaxique YAML (Python PyYAML parser) !"
        STATUS=1
        YAML_VALIDATOR_FOUND=1
    fi
fi

if [ "${YAML_VALIDATOR_FOUND}" -eq 0 ]; then
    echo "ℹ️  Aucun parseur YAML avancé (Ruby / PyYAML) disponible — contrôle structurel de base conservé."
fi

# 3. Contrôle de conformité des icônes (Règle d'or Glance : si: ou mdi: uniquement)
echo "--- Étape 2 : Standardisation des icônes (si: ou mdi:) ---"
ICONS=$(grep -E '^[[:space:]]*icon:' "${GLANCE_FILE}" | sed -E 's/^[[:space:]]*icon:[[:space:]]*//' | tr -d '"'"'" | sort -u || true)

ICON_ERRORS=0
if [ -z "${ICONS}" ]; then
    echo "⚠️ Avertissement : Aucune icône trouvée dans ${GLANCE_FILE}."
else
    while IFS= read -r icon; do
        [ -z "${icon}" ] && continue
        if [[ ! "${icon}" =~ ^(si|mdi):[a-z0-9-]+$ ]]; then
            echo "❌ ERREUR : L'icône '${icon}' ne respecte pas le standard Homelab (doit strictly débuter par 'si:' ou 'mdi:')."
            ICON_ERRORS=$((ICON_ERRORS + 1))
            STATUS=1
        fi
    done <<< "${ICONS}"

    if [ "${ICON_ERRORS}" -eq 0 ]; then
        TOTAL_ICONS=$(echo "${ICONS}" | wc -l | tr -d ' ')
        echo "✅ Toutes les icônes (${TOTAL_ICONS}) sont conformes au standard monochromatique ('si:' ou 'mdi:')."
    fi
fi

# 4. Contrôle de parité des variables d'environnement (${VAR})
echo "--- Étape 3 : Parité des variables d'environnement ---"
VARS=$(grep -oE '\$\{[A-Za-z0-9_]+\}' "${GLANCE_FILE}" | sed -E 's/^\$\{([A-Za-z0-9_]+)\}$/\1/' | sort -u || true)

VAR_ERRORS=0
if [ -z "${VARS}" ]; then
    echo "ℹ️  Aucune variable interpolée trouvée dans ${GLANCE_FILE}."
else
    while IFS= read -r var; do
        [ -z "${var}" ] && continue

        # Vérifier si la variable est présente dans le fichier env
        LINE=$(grep -E "^[[:space:]]*${var}=" "${ENV_FILE}" || true)

        if [ -z "${LINE}" ]; then
            echo "❌ ERREUR : La variable '\${${var}}' est utilisée dans ${GLANCE_FILE} mais NON DÉCLARÉE dans ${ENV_FILE} !"
            VAR_ERRORS=$((VAR_ERRORS + 1))
            STATUS=1
        else
            VAL="${LINE#*=}"
            # En mode runtime sur le serveur, la valeur ne doit pas être vide
            if [ "${RUNTIME_MODE}" -eq 1 ]; then
                if [ -z "${VAL}" ]; then
                    echo "❌ ERREUR RUNTIME : La variable '${var}' est vide dans ${ENV_FILE} !"
                    VAR_ERRORS=$((VAR_ERRORS + 1))
                    STATUS=1
                elif [[ "${VAL}" =~ (votre-domaine|your_domain|192\.168\.x\.x) ]]; then
                    echo "⚠️ AVERTISSEMENT RUNTIME : La variable '${var}' semble contenir un placeholder non remplacé : ${VAL}"
                fi
            fi
        fi
    done <<< "${VARS}"

    if [ "${VAR_ERRORS}" -eq 0 ]; then
        TOTAL_VARS=$(echo "${VARS}" | wc -l | tr -d ' ')
        echo "✅ Toutes les variables interpolées (${TOTAL_VARS}) sont correctement définies dans ${ENV_FILE}."
    fi
fi

# 5. Contrôle des variables orphelines dans le fichier .env
echo "--- Étape 4 : Détection des variables orphelines ---"
ENV_VARS=$(grep -E '^[[:space:]]*URL_[A-Za-z0-9_]+=' "${ENV_FILE}" | cut -d'=' -f1 | tr -d ' ' | sort -u || true)

if [ -n "${ENV_VARS}" ]; then
    while IFS= read -r env_var; do
        [ -z "${env_var}" ] && continue
        if ! grep -q "\${${env_var}}" "${GLANCE_FILE}"; then
            echo "ℹ️  INFO : '${env_var}' est déclarée dans ${ENV_FILE} mais n'est pas référencée dans ${GLANCE_FILE}."
        fi
    done <<< "${ENV_VARS}"
fi

echo "=============================================================================="
if [ "${STATUS}" -eq 0 ]; then
    echo "🎉 CONTRÔLE RÉUSSI : La configuration de Glance est parfaitement saine et sécurisée."
    exit 0
else
    echo "🚨 CONTRÔLE ÉCHOUÉ : Corrigez les erreurs ci-dessus avant de déployer ou redémarrer Glance."
    exit 1
fi
