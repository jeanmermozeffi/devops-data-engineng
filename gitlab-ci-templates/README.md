# AKILIYA — GitLab CI Templates

Templates CI/CD réutilisables pour tous les projets du groupe AKILIYA.

## Structure

```
gitlab-ci-templates/
├── shared-jobs.yml      ← Jobs partagés (secrets scan, docker push, notify)
├── nextjs-pipeline.yml  ← Pipeline complet Next.js
├── fastapi-pipeline.yml ← Pipeline complet FastAPI
└── README.md
```

## Utilisation dans un projet

### Projet Next.js (minimal)

```yaml
# .gitlab-ci.yml du projet
include:
  - project: 'akiliya/infra/gitlab-ci-templates'
    ref: main
    file: '/nextjs-pipeline.yml'

variables:
  IMAGE_NAME: "mon-projet-frontend"
  PROD_DOMAIN: "app.mon-saas.com"
  STAGING_DOMAIN: "staging-app.mon-saas.com"
```

### Projet FastAPI (minimal)

```yaml
# .gitlab-ci.yml du projet
include:
  - project: 'akiliya/infra/gitlab-ci-templates'
    ref: main
    file: '/fastapi-pipeline.yml'

variables:
  IMAGE_NAME: "mon-projet-api"
  PROD_DOMAIN: "api.mon-saas.com"
  STAGING_DOMAIN: "staging-api.mon-saas.com"
```

## Variables GitLab à configurer

### Niveau groupe AKILIYA (hérités par tous les projets)

| Variable | Description | Protégée | Masquée |
|---|---|---|---|
| `DOCKER_TOKEN` | Token Docker Hub | ✓ | ✓ |
| `VPS_SSH_KEY_B64` | Clé SSH encodée en base64¹ | ✓ | ✓ |
| `VPS_HOST` | IP du VPS | ✓ | — |
| `VPS_USER` | Utilisateur SSH VPS | ✓ | — |
| `SLACK_WEBHOOK_URL` | Webhook notifications | ✓ | ✓ |

> ¹ **Pourquoi base64 ?** GitLab refuse de masquer les variables contenant des sauts de ligne
> (caractères whitespace). La clé SSH brute en contient → erreur à la création.
> Solution : `base64 -w 0 ~/.ssh/id_rsa | tr -d '\n'` puis coller le résultat.

### Niveau projet (spécifiques)

| Variable | Description | Exemple |
|---|---|---|
| `IMAGE_NAME` | Nom image Docker Hub | `akitext-plateforme-core` |
| `PROD_DOMAIN` | Domaine production | `app.akitext.com` |
| `STAGING_DOMAIN` | Domaine staging | `staging-app.akitext.com` |

## Flux par branche

| Branche | Stages déclenchés | Résultat |
|---|---|---|
| `main` | lint → build/test → security → push → deploy prod → notify | Deploy production |
| `staging` | lint → build/test → security → push → deploy staging → notify | Deploy staging |
| `dev` | lint → build/test → push → deploy dev | Deploy dev |
| MR | lint → build/test | Validation uniquement |

## Surcharger un job

```yaml
include:
  - project: 'akiliya/infra/gitlab-ci-templates'
    ref: main
    file: '/nextjs-pipeline.yml'

variables:
  IMAGE_NAME: "mon-projet"

# Surcharger uniquement le job de deploy
deploy:vps:
  extends: .job:deploy-ssh
  script:
    - echo "Logic de deploy spéciale"
```
