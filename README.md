# Conteneurs Addok pour Docker

Ces images permettent de simplifier grandement la mise en place d'une instance [addok](https://github.com/addok/addok) avec les données de références diffusées par la [Base Adresse Nationale](https://adresse.data.gouv.fr).

## Plateformes

Les images Docker sont disponibles pour `linux/amd64` et `linux/arm64`. Elles sont donc parfaitement utilisables sur Apple Silicon ou Raspberry Pi sans couche d’émulation.

## Composants installés

| Nom du composant | Version |
| --- | --- |
| `redis` | `7.x` |
| `python` | `3.10.x` |
| `addok` | `1.0.3` |
| `addok-fr` | `1.0.1` |
| `addok-france` | `1.1.3` |
| `addok-csv` | `1.0.1` |
| `addok-sqlite-store` | `1.0.1` |
| `gunicorn` | `20.1.0` |

## Guides d'installation

Les guides suivants ont été rédigés pour un environnement Linux ou Mac. Ils peuvent être adaptés pour Windows.

### Pré-requis

* Au moins 6 Go de RAM disponible (à froid)
* 8 Go d'espace disque disponible (hors logs)
* [Docker CE 1.10+](https://docs.docker.com/engine/installation/)
* [Docker Compose 1.10+](https://docs.docker.com/compose/install/)
* `unzip` ou équivalent
* `wget` ou équivalent

### Installer une instance avec les données de la Base Adresse Nationale

Tout d'abord placez vous dans un dossier de travail, appelez-le par exemple `ban`.

#### Télécharger les données pré-indexées

```bash
wget https://adresse.data.gouv.fr/data/ban/adresses/latest/addok/addok-france-bundle.zip
```

#### Décompresser l'archive

```bash
mkdir addok-data
unzip -d addok-data addok-france-bundle.zip
```

#### Télécharger le fichier Compose

```bash
wget https://raw.githubusercontent.com/BaseAdresseNationale/addok-docker/master/docker-compose.yml
```

#### Démarrer l'instance

Suivant votre environnement, `sudo` peut être nécessaire pour les commandes suivantes.

```bash
# Attachée au terminal
docker-compose up

# ou en arrière-plan
docker-compose up -d
```

Suivant les performances de votre machine, l'instance mettra entre 30 secondes et 2 minutes à démarrer effectivement, le temps de charger les données dans la mémoire vive.

* 90 secondes sur une VPS-SSD-3 OVH (2 vCPU, 8 Go)
* 50 secondes sur une VM EG-15 OVH (4 vCPU, 15 Go)

Par défaut l'instance écoute sur le port `7878`.

#### Tester l'instance

```bash
curl "http://localhost:7878/search?q=1+rue+de+la+paix+paris"
```

### Paramètres avancés

| Nom du paramètre | Description |
| ----- | ----- |
| `WORKERS` | Nombre de workers addok à lancer. Valeur par défaut : `1`. |
| `WORKER_TIMEOUT` | [Durée maximale allouée à un worker](http://docs.gunicorn.org/en/0.17.2/configure.html#timeout) pour effectuer une opération de géocodage. Valeur par défaut : `30`. |




 

# Azure Déploiement

## Architecture déployée (`infra/main.bicep`)

Le fichier `main.bicep` provisionne automatiquement l’infrastructure suivante sur Azure :
- **Azure Container Apps Environment** : Environnement d’exécution pour les applications conteneurisées.
- **Container Apps** :
  - `addok` (service principal exposé sur le port 7878)
  - `addok-redis` (service Redis pour Addok)
- **Stockage Azure** :
  - Compte de stockage pour les données Addok et les logs, avec partages de fichiers Azure (Azure File Share) montés dans les conteneurs.
- **Log Analytics Workspace** & **Application Insights** : Pour la collecte et la supervision des logs et métriques.

## Procédure de déploiement

1. **Authentification Azure**
   ```bash
   azd auth login
   ```

2. **Déploiement de l’infrastructure**
   ```bash
   azd up
   ```
   Cette commande déploie tous les composants définis dans `infra/main.bicep`.

3. **Chargement des données dans le stockage Azure**
   Récupérez les variables d’environnement générées :
   ```bash
   AZURE_RESOURCE_GROUP=$(azd env get-value AZURE_RESOURCE_GROUP)
   AZURE_STORAGE_ACCOUNT=$(azd env get-value STORAGE_ACCOUNT_NAME)
   ./upload.sh $AZURE_RESOURCE_GROUP $AZURE_STORAGE_ACCOUNT
   ```
   Le script `upload.sh` charge les données nécessaires dans le partage de fichiers Azure.

5. **Redémarrage du service**
   
   ```bash
   AZURE_RESOURCE_GROUP=$(azd env get-value AZURE_RESOURCE_GROUP)
   az login
   az containerapp update --name addokapp -g $AZURE_RESOURCE_GROUP --set-env-vars RESTART_TRIGGER=$(date +%s) --container-name addok
   # Test l'etat du service
   az containerapp revision list -n addokapp -g $AZURE_RESOURCE_GROUP --output table
   ```

6. **Récupérer l’URL publique de l’API Addok**
   ```bash
   ADDOK_FQDN=$(azd env get-value ADDOK_FQDN)
   curl "https://${ADDOK_FQDN}/search?q=1+rue+de+la+paix+paris"
   ```

## Personnalisation

Les paramètres principaux (nombre de workers, timeout, logs, etc.) sont configurables dans le fichier Bicep via les paramètres :
- `WORKERS`
- `WORKER_TIMEOUT`
- `LOG_QUERIES`
- `LOG_NOT_FOUND`
- `SLOW_QUERIES`

Vous pouvez les ajuster dans le fichier `main.parameters.json` avant le déploiement.

