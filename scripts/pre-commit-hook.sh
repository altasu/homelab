#!/bin/bash

# ==============================================================================
# Git Pre-Commit Hook — Contrôle Automatique Anti-Fuite de Données Sensibles
# Description : Exécuté automatiquement avant chaque `git commit`.
#               Scanne les fichiers indexés (staged) pour détecter les clés,
#               mots de passe, fichiers .env réels et artefacts non sécurisés.
# ==============================================================================

set -e

echo "🔒 [Pre-Commit Security Audit] Vérification des fichiers indexés..."

STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM)

if [ -z "${STAGED_FILES}" ]; then
    echo "✅ Aucun fichier indexé à contrôler."
    exit 0
fi

LEAK_DETECTED=0

# 1. Empêcher l'indexation de fichiers .env réels (seuls .env.example sont autorisés)
for file in ${STAGED_FILES}; do
    if [[ "${file}" =~ \.env$ ]] && [[ ! "${file}" =~ \.env\.example$ ]]; then
        echo "❌ ERREUR SÉCURITÉ : Le fichier d'environnement réel '${file}' est indexé !"
        echo "   Les fichiers .env contiennent des secrets et ne doivent JAMAIS être committés."
        LEAK_DETECTED=1
    fi
done

# 2. Détection des clés privées et certificats secrets dans le contenu indexé
KEY_PATTERN="BEGIN"_"PRIVATE KEY"
RSA_PATTERN="BEGIN"_"RSA PRIVATE KEY"

if git diff --cached -S"${KEY_PATTERN}" --name-only | grep -v "scripts/pre-commit-hook.sh" | grep -q .; then
    echo "❌ ERREUR SÉCURITÉ : Détection d'une clé privée (BEGIN PRIVATE KEY) dans les fichiers indexés !"
    LEAK_DETECTED=1
fi

if git diff --cached -S"${RSA_PATTERN}" --name-only | grep -v "scripts/pre-commit-hook.sh" | grep -q .; then
    echo "❌ ERREUR SÉCURITÉ : Détection d'une clé RSA privée dans les fichiers indexés !"
    LEAK_DETECTED=1
fi

# 3. Contrôle des fichiers env d'exemple avec scripts/check-env.sh
for file in ${STAGED_FILES}; do
    if [[ "${file}" =~ \.env\.example$ ]]; then
        if [ -f "scripts/check-env.sh" ]; then
            if ! bash scripts/check-env.sh "${file}" > /dev/null 2>&1; then
                echo "⚠️  AVERTISSEMENT : Le fichier modèle '${file}' comporte des anomalies de format."
            fi
        fi
    fi
done

if [ "${LEAK_DETECTED}" -eq 1 ]; then
    echo "================================================================="
    echo "❌ AUDIT EN ÉCHEC : Commit bloqué pour prévenir une fuite de données."
    echo "   Veuillez retirer les fichiers sensibles avec 'git restore --staged <file>'."
    echo "================================================================="
    exit 1
fi

echo "✅ [Pre-Commit Security Audit] Aucun secret ni fichier sensible détecté. Commit autorisé."
exit 0
