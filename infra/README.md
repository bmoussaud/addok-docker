# Configuration Terraform pour Addok sur Azure Container Apps

Ce répertoire contient les fichiers de configuration Terraform pour déployer la pile Addok sur Azure Container Apps. La configuration est traduite à partir du modèle Bicep original et fournit les mêmes ressources d'infrastructure.

## Architecture

La configuration Terraform déploie les ressources Azure suivantes :

- **Espace de travail Log Analytics** - Pour la journalisation centralisée
- **Application Insights** - Pour la surveillance et la télémétrie des applications
- **Compte de stockage** - Pour le stockage de données persistant avec partages de fichiers et files d'attente
- **Environnement Container Apps** - Environnement géré pour les applications conteneurisées
- **Container Apps** :
  - Application principale Addok (avec sidecar d'importation)
  - Serveur Redis pour la mise en cache
  - Proxy inverse Nginx
- **Tâche Container App** - Tâche planifiée pour l'import de données
- **Rubrique système Event Grid** - Pour les notifications d'événements de stockage
- **Identité gérée attribuée par l'utilisateur** - Pour l'authentification ACR
- **Attributions de rôles** - Pour les permissions appropriées

## Prérequis

1. **Terraform** installé (>= 1.0)
2. **Azure CLI** installé et authentifié
3. **Azure Container Registry existant** avec les images Addok
4. **Groupe de ressources** déjà créé

## Fichiers

- `main.tf` - Configuration Terraform principale
- `variables.tf` - Définitions des variables
- `outputs.tf` - Valeurs de sortie
- `versions.tf` - Contraintes de version des fournisseurs
- `terraform.tfvars.example` - Exemples de valeurs de variables

## Utilisation

### 1. Préparer les variables

Copiez le fichier d'exemple de variables et mettez-le à jour avec vos valeurs :

```bash
cp terraform.tfvars.example terraform.tfvars
```

Modifiez `terraform.tfvars` avec vos valeurs spécifiques :

```hcl
environment_name     = "addok-dev"
location            = "East US"
resource_group_name = "rg-addok-dev"
resource_group_id   = "/subscriptions/YOUR_SUBSCRIPTION_ID/resourceGroups/rg-addok-dev"
acr_name            = "your-acr-name"

# Configuration optionnelle
acr_addok_importer_image_tag = "latest"
workers                      = 1
worker_timeout              = 30
log_queries                 = 1
log_not_found               = 1
slow_queries                = 200
```

### 2. Initialiser Terraform

```bash
terraform init
```

### 3. Valider la configuration

```bash
terraform validate
```

### 4. Planifier le déploiement

```bash
terraform plan
```

### 5. Appliquer la configuration

```bash
terraform apply -auto-approve
```

## Notes importantes

### Exigences du registre de conteneurs

La configuration fait référence à un Azure Container Registry existant qui doit contenir :
- `etalab/addok` - Image de l'application principale Addok
- `etalab/addok-redis` - Image du serveur Redis
- `etalab/addok-importer-aca` - Image de l'importateur Addok

### Permissions de l'identité gérée

La configuration crée une identité gérée attribuée par l'utilisateur avec attribution du rôle AcrPull pour accéder au registre de conteneurs.

### Configuration de stockage

Deux partages de fichiers Azure sont créés :
- `addokfileshare` - Pour les données et la configuration de l'application
- `addoklogfileshare` - Pour les journaux de l'application

### Architecture pilotée par les événements

Une rubrique système Event Grid est configurée pour se déclencher sur les événements de stockage (fichier créé, supprimé, renommé) et transmet les événements à une file d'attente de stockage.

## Sorties

Après un déploiement réussi, les sorties suivantes sont disponibles :

- `addok_fqdn` - FQDN de l'application Addok
- `storage_account_name` - Nom du compte de stockage
- `acr_name` - Nom du registre de conteneurs
- `azure_container_registry_endpoint` - Serveur de connexion du registre de conteneurs
- `log_analytics_workspace_id` - ID de l'espace de travail Log Analytics
- `application_insights_id` - ID du composant Application Insights
- `container_app_environment_id` - ID de l'environnement Container Apps

## Dépannage

### Problèmes courants

1. **Accès au registre de conteneurs** : Assurez-vous que l'ACR contient les images requises et que l'identité gérée dispose des permissions appropriées.

2. **Groupe de ressources** : Le groupe de ressources doit exister avant d'exécuter Terraform.

3. **Conflits de nommage** : Si des ressources avec des noms similaires existent déjà, modifiez la variable `environment_name`.

4. **Disponibilité de région** : Assurez-vous que Container Apps est disponible dans votre région Azure choisie.

### Étapes de validation

Après le déploiement, vérifiez :

1. Les applications conteneurisées fonctionnent : Vérifiez le portail Azure ou utilisez Azure CLI
2. L'application est accessible : Testez le point de terminaison FQDN d'Addok
3. Les journaux circulent : Vérifiez l'espace de travail Log Analytics pour les journaux d'application
4. Intégration de stockage : Vérifiez que les partages de fichiers sont montés correctement

## Migration depuis Bicep

Cette configuration Terraform fournit des fonctionnalités équivalentes au modèle `main.bicep` original avec les considérations suivantes :

- Le nommage des ressources utilise un jeton aléatoire pour l'unicité
- Tous les paramètres originaux sont pris en charge comme variables Terraform
- Les sorties correspondent aux sorties Bicep originales
- Les dépendances et l'ordre sont préservés

## Nettoyage

Pour détruire toutes les ressources :

```bash
terraform destroy
```

**Attention** : Cela supprimera définitivement toutes les ressources créées par cette configuration.
