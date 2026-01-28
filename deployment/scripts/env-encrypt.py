#!/usr/bin/env python3
"""
Gestionnaire de secrets chiffrés pour fichiers .env

Chiffre et déchiffre les valeurs sensibles dans les fichiers .env
en utilisant Fernet (chiffrement symétrique basé sur AES)

Usage:
    # Générer une clé de chiffrement
    python env-encrypt.py generate-key

    # Chiffrer un fichier .env
    python env-encrypt.py encrypt .env.dev

    # Déchiffrer un fichier .env
    python env-encrypt.py decrypt .env.dev.encrypted

    # Chiffrer une valeur spécifique
    python env-encrypt.py encrypt-value "mon-secret"
"""

import sys
import argparse
from pathlib import Path
from cryptography.fernet import Fernet
import yaml


class EnvEncryptor:
    """Gestionnaire de chiffrement pour fichiers .env"""

    def __init__(self, key_path: str = ".env.key", config_path: str = None):
        """
        Initialise le gestionnaire avec une clé de chiffrement

        Args:
            key_path: Chemin vers le fichier contenant la clé
            config_path: Chemin vers le fichier de configuration YAML (optionnel)
        """
        self.key_path = Path(key_path)
        self.key = self._load_or_generate_key()
        self.cipher = Fernet(self.key)

        # Charger la configuration des variables sensibles
        self.config = self._load_config(config_path)

    def _load_config(self, config_path: str = None) -> dict:
        """
        Charge la configuration des variables sensibles depuis YAML

        Args:
            config_path: Chemin vers le fichier YAML de configuration

        Returns:
            Dictionnaire de configuration
        """
        # Chemin par défaut : même dossier que le script
        if config_path is None:
            script_dir = Path(__file__).parent
            config_path = script_dir / "sensitive-vars.yml"
        else:
            config_path = Path(config_path)

        # Configuration par défaut si le fichier n'existe pas
        default_config = {
            'sensitive_patterns': [
                'PASSWORD', 'SECRET', 'KEY', 'TOKEN', 'PRIVATE',
                'DATABASE_PASSWORD', 'JWT_SECRET_KEY', 'GITHUB_TOKEN',
                'REDIS_PASSWORD', 'API_KEY', 'SECRET_KEY'
            ],
            'exclude_patterns': ['PUBLIC_KEY', 'JWT_PUBLIC_KEY'],
            'ignore_values': ['changeme', 'CHANGEZ_CETTE_CLE', ''],
            'options': {
                'case_sensitive': False,
                'exact_match': False,
                'partial_match': True,
                'warn_on_sensitive_in_clear': True,
                'encrypted_marker_prefix': 'ENC[',
                'encrypted_marker_suffix': ']',
                'output_file_permissions': 0o600
            }
        }

        # Charger depuis YAML si le fichier existe
        if config_path.exists():
            try:
                with config_path.open('r') as f:
                    loaded_config = yaml.safe_load(f)
                    # Fusionner avec les valeurs par défaut
                    if loaded_config:
                        default_config.update(loaded_config)
                    print(f"📋 Configuration chargée depuis {config_path}")
            except Exception as e:
                print(f"⚠️  Erreur lors du chargement de {config_path}: {e}")
                print(f"   Utilisation de la configuration par défaut")
        else:
            print(f"ℹ️  Fichier {config_path} non trouvé, utilisation de la configuration par défaut")

        return default_config

    def _is_sensitive(self, var_name: str) -> bool:
        """
        Détermine si une variable est sensible selon la configuration

        Args:
            var_name: Nom de la variable

        Returns:
            True si la variable doit être chiffrée
        """
        options = self.config.get('options', {})
        sensitive_patterns = self.config.get('sensitive_patterns', [])
        exclude_patterns = self.config.get('exclude_patterns', [])

        # Normaliser le nom selon case_sensitive
        if not options.get('case_sensitive', False):
            var_name_check = var_name.upper()
            sensitive_patterns = [p.upper() for p in sensitive_patterns]
            exclude_patterns = [p.upper() for p in exclude_patterns]
        else:
            var_name_check = var_name

        # Vérifier si dans exclude_patterns
        for exclude in exclude_patterns:
            if options.get('exact_match', False):
                if var_name_check == exclude:
                    return False
            else:
                if exclude in var_name_check:
                    return False

        # Vérifier si dans sensitive_patterns
        for pattern in sensitive_patterns:
            if options.get('exact_match', False):
                if var_name_check == pattern:
                    return True
            else:
                if pattern in var_name_check:
                    return True

        return False

    def _should_ignore_value(self, value: str) -> bool:
        """
        Détermine si une valeur doit être ignorée (non chiffrée)

        Args:
            value: Valeur à vérifier

        Returns:
            True si la valeur doit être ignorée
        """
        ignore_values = self.config.get('ignore_values', [])

        # Normaliser
        value_check = value.strip().upper()

        for ignore in ignore_values:
            # Gérer les valeurs None ou vides depuis le YAML
            if ignore is None:
                continue

            # Convertir en string si nécessaire
            ignore_str = str(ignore)

            if value_check == ignore_str.upper() or value == ignore_str:
                return True

        return False

    def _load_or_generate_key(self) -> bytes:
        """Charge ou génère une nouvelle clé de chiffrement"""
        if self.key_path.exists():
            print(f"📖 Chargement de la clé depuis {self.key_path}")
            return self.key_path.read_bytes()
        else:
            print(f"🔑 Génération d'une nouvelle clé: {self.key_path}")
            key = Fernet.generate_key()
            self.key_path.write_bytes(key)
            self.key_path.chmod(0o600)  # Lecture/écriture owner seulement
            print(f"⚠️  IMPORTANT: Sauvegardez cette clé en lieu sûr !")
            print(f"   Clé: {key.decode()}")
            return key

    def encrypt_value(self, value: str) -> str:
        """
        Chiffre une valeur

        Args:
            value: Valeur à chiffrer

        Returns:
            Valeur chiffrée (base64)
        """
        encrypted = self.cipher.encrypt(value.encode())
        return encrypted.decode()

    def decrypt_value(self, encrypted_value: str) -> str:
        """
        Déchiffre une valeur

        Args:
            encrypted_value: Valeur chiffrée (base64)

        Returns:
            Valeur déchiffrée
        """
        decrypted = self.cipher.decrypt(encrypted_value.encode())
        return decrypted.decode()

    def encrypt_file(self, input_file: str, output_file: str = None):
        """
        Chiffre un fichier .env

        Args:
            input_file: Fichier .env en clair
            output_file: Fichier .env chiffré (défaut: input_file.encrypted)
        """
        input_path = Path(input_file)
        output_path = Path(output_file or f"{input_file}.encrypted")

        print(f"🔒 Chiffrement de {input_path} → {output_path}")

        if not input_path.exists():
            print(f"❌ Fichier {input_path} introuvable")
            return

        options = self.config.get('options', {})
        prefix = options.get('encrypted_marker_prefix', 'ENC[')
        suffix = options.get('encrypted_marker_suffix', ']')

        # ✅ Charger le fichier de sortie existant pour vérifier les variables déjà chiffrées
        already_encrypted_vars = {}
        if output_path.exists():
            print(f"📋 Vérification du fichier existant: {output_path}")
            with output_path.open('r') as f:
                for line in f:
                    line = line.strip()
                    if '=' in line and not line.startswith('#'):
                        key, value = line.split('=', 1)
                        key = key.strip()
                        value = value.strip()
                        # Si la valeur est chiffrée, la stocker
                        if value.startswith(prefix) and value.endswith(suffix):
                            already_encrypted_vars[key] = value

        lines_out = []
        encrypted_count = 0
        already_encrypted_count = 0
        reused_count = 0

        with input_path.open('r') as f:
            for line in f:
                line = line.rstrip()

                # Ligne vide ou commentaire
                if not line or line.startswith('#'):
                    lines_out.append(line)
                    continue

                # Ligne avec variable
                if '=' in line:
                    key, value = line.split('=', 1)
                    key = key.strip()
                    value = value.strip()

                    # Enlever les quotes si présentes
                    if value.startswith('"') and value.endswith('"'):
                        value = value[1:-1]
                    elif value.startswith("'") and value.endswith("'"):
                        value = value[1:-1]

                    # ✅ Vérifier si déjà chiffré dans le fichier source (double chiffrement)
                    if value.startswith(prefix) and value.endswith(suffix):
                        lines_out.append(line)
                        already_encrypted_count += 1
                        print(f"  ⏭️  {key}: déjà chiffré dans la source (ignoré)")
                        continue

                    # ✅ Vérifier si déjà présent dans le fichier de sortie existant
                    if key in already_encrypted_vars:
                        # Réutiliser la valeur déjà chiffrée
                        lines_out.append(f"{key}={already_encrypted_vars[key]}")
                        reused_count += 1
                        print(f"  ♻️  {key}: réutilisé depuis {output_path.name}")
                        continue

                    # Vérifier si la variable est sensible
                    is_sensitive = self._is_sensitive(key)
                    should_ignore = self._should_ignore_value(value)

                    if is_sensitive and not should_ignore and value:
                        # Chiffrer la valeur
                        encrypted = self.encrypt_value(value)
                        lines_out.append(f"{key}={prefix}{encrypted}{suffix}")
                        encrypted_count += 1
                        print(f"  🔐 {key}: chiffré")
                    else:
                        lines_out.append(line)

                        # Avertissement si variable sensible mais valeur ignorée
                        if is_sensitive and should_ignore:
                            print(f"  ⚠️  {key}: ignoré (valeur par défaut)")
                else:
                    lines_out.append(line)

        # Écrire le fichier chiffré
        output_path.write_text('\n'.join(lines_out) + '\n')

        # Permissions du fichier (convertir en int si string)
        perms = options.get('output_file_permissions', 384)  # 384 = 0o600
        if isinstance(perms, str):
            # Gérer les notations octales en string
            if perms.startswith('0o') or perms.startswith('0O'):
                perms = int(perms, 8)
            else:
                perms = int(perms)
        output_path.chmod(perms)

        print(f"✅ {encrypted_count} variable(s) nouvellement chiffrée(s)")
        if reused_count > 0:
            print(f"♻️  {reused_count} variable(s) réutilisée(s) (déjà chiffrées)")
        if already_encrypted_count > 0:
            print(f"ℹ️  {already_encrypted_count} variable(s) déjà chiffrée(s) dans la source (ignorées)")
        print(f"📄 Fichier chiffré: {output_path}")

    def decrypt_file(self, input_file: str, output_file: str = None):
        """
        Déchiffre un fichier .env

        Args:
            input_file: Fichier .env chiffré
            output_file: Fichier .env en clair (défaut: sans .encrypted)
        """
        input_path = Path(input_file)

        if output_file:
            output_path = Path(output_file)
        else:
            # Enlever .encrypted du nom si présent
            output_path = Path(str(input_path).replace('.encrypted', ''))

        print(f"🔓 Déchiffrement de {input_path} → {output_path}")

        if not input_path.exists():
            print(f"❌ Fichier {input_path} introuvable")
            return

        options = self.config.get('options', {})
        prefix = options.get('encrypted_marker_prefix', 'ENC[')
        suffix = options.get('encrypted_marker_suffix', ']')

        lines_out = []
        decrypted_count = 0

        with input_path.open('r') as f:
            for line in f:
                line = line.rstrip()

                # Ligne vide ou commentaire
                if not line or line.startswith('#'):
                    lines_out.append(line)
                    continue

                # Ligne avec variable
                if '=' in line:
                    key, value = line.split('=', 1)
                    key = key.strip()
                    value = value.strip()

                    # Déchiffrer si valeur chiffrée (format configurable)
                    if value.startswith(prefix) and value.endswith(suffix):
                        # Extraire la valeur chiffrée
                        encrypted_value = value[len(prefix):-len(suffix)]
                        try:
                            decrypted = self.decrypt_value(encrypted_value)
                            lines_out.append(f'{key}="{decrypted}"')
                            decrypted_count += 1
                            print(f"  🔓 {key}: déchiffré")
                        except Exception as e:
                            print(f"  ⚠️  {key}: erreur de déchiffrement ({e})")
                            lines_out.append(line)
                    else:
                        lines_out.append(line)
                else:
                    lines_out.append(line)

        # Écrire le fichier déchiffré
        output_path.write_text('\n'.join(lines_out) + '\n')

        # Permissions du fichier
        perms = options.get('output_file_permissions', 0o600)
        output_path.chmod(perms)

        print(f"✅ {decrypted_count} variable(s) déchiffrée(s)")
        print(f"📄 Fichier déchiffré: {output_path}")


def main():
    parser = argparse.ArgumentParser(
        description='Gestionnaire de secrets chiffrés pour fichiers .env',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Exemples:
  # Générer une clé
  %(prog)s generate-key
  
  # Chiffrer .env.dev
  %(prog)s encrypt .env.dev
  
  # Déchiffrer .env.dev.encrypted
  %(prog)s decrypt .env.dev.encrypted
  
  # Chiffrer une valeur
  %(prog)s encrypt-value "mon-secret"
  
  # Déchiffrer une valeur
  %(prog)s decrypt-value "gAAAAA..."
        """
    )

    parser.add_argument(
        'action',
        choices=['generate-key', 'encrypt', 'decrypt', 'encrypt-value', 'decrypt-value'],
        help='Action à effectuer'
    )
    parser.add_argument(
        'input',
        nargs='?',
        help='Fichier ou valeur à traiter'
    )
    parser.add_argument(
        '-o', '--output',
        help='Fichier de sortie (optionnel)'
    )
    parser.add_argument(
        '-k', '--key-file',
        default='.env.key',
        help='Fichier contenant la clé de chiffrement (défaut: .env.key)'
    )

    args = parser.parse_args()

    if args.action == 'generate-key':
        key = Fernet.generate_key()
        key_path = Path(args.key_file)
        key_path.write_bytes(key)
        key_path.chmod(0o600)
        print(f"✅ Clé générée: {args.key_file}")
        print(f"🔑 Clé: {key.decode()}")
        print(f"⚠️  Sauvegardez cette clé en lieu sûr !")
        return

    # Pour les autres actions, on a besoin d'un input
    if not args.input:
        print(f"❌ Erreur: argument 'input' requis pour l'action '{args.action}'")
        parser.print_help()
        sys.exit(1)

    encryptor = EnvEncryptor(args.key_file)

    if args.action == 'encrypt':
        encryptor.encrypt_file(args.input, args.output)

    elif args.action == 'decrypt':
        encryptor.decrypt_file(args.input, args.output)

    elif args.action == 'encrypt-value':
        encrypted = encryptor.encrypt_value(args.input)
        print(f"🔒 Valeur chiffrée:")
        print(f"   ENC[{encrypted}]")

    elif args.action == 'decrypt-value':
        # Enlever ENC[ et ] si présent
        value = args.input
        if value.startswith('ENC[') and value.endswith(']'):
            value = value[4:-1]
        decrypted = encryptor.decrypt_value(value)
        print(f"🔓 Valeur déchiffrée:")
        print(f"   {decrypted}")


if __name__ == '__main__':
    main()

