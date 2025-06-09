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


# Déploiement Addok sur Azure via le Portail Azure

Ce guide explique comment déployer l’infrastructure Addok (équivalent du fichier `main.bicep`) en utilisant le portail Azure.

---

## 1. Créer un groupe de ressources

- Accédez à **Groupes de ressources** > **Créer**.
- Renseignez le nom et la région.
- ![Capture d’écran - Création groupe de ressources](screenshots/01-resource-group.png)

---

## 2. Créer un Log Analytics Workspace

- Accédez à **Log Analytics workspaces** > **Créer**.
- Remplissez les champs requis.
- ![Capture d’écran - Log Analytics](screenshots/02-log-analytics.png)

---

## 3. Créer une Application Insights

- Accédez à **Application Insights** > **Créer**.
- Sélectionnez le même groupe de ressources et la même région.
- Liez-le au Log Analytics Workspace créé précédemment.
- ![Capture d’écran - Application Insights](screenshots/03-app-insights.png)

---

## 4. Créer un compte de stockage

- Accédez à **Comptes de stockage** > **Créer**.
- Choisissez le type **StorageV2** et activez **Large file shares**.
- Primary Service: **Azure Files**
- Performance **Standard**
- Option par défault.
- Deuxieme Page: 
   - `Allow enabling anonymous access on individual containers`
- ![Capture d’écran - Compte de stockage](screenshots/04-storage-account.png)
- ![Capture d’écran - Compte de stockage 2](screenshots/04-storage-account-2.png)

---

## 5. Créer deux Azure File Shares

- Dans le compte de stockage, allez dans **Partages de fichiers** > **Ajouter** :
  - `addokfileshare` (quota 10 Go)
  - `addoklogfileshare` (quota 10 Go)
- Décoche `Backup`
- ![Capture d’écran - File Share](screenshots/05-file-share.png)

---

## 6. Créer un environnement Azure Container Apps

- Accédez à **Container Apps Environments** > **Créer**.
- Renseignez le nom, la région, rattachez le Log Analytics Workspace.
- ![Capture d’écran - Environnement Container Apps](screenshots/06-container-env.png)

---

## 7. Créer l’application Container App principale (`addokapp`)

- Accédez à **Container Apps** > **Créer**.
- Creer un nouvel environement 
- Ajoutez le conteneur `etalab/addok` utisant le Docker Hub
- Configurez les variables d’environnement (`WORKERS`, `WORKER_TIMEOUT`, etc.).
- Configurez l’ingress (port 7878, public).
- Ajoutez les montages de volumes Azure File Share (`addokfileshare` et `addoklogfileshare`) aux bons chemins (`/data`, `/etc/addok`, `/logs`).
- Ajoutez les probes de démarrage, liveness, readiness sur le port 7878.
- ![Capture d’écran - Environnement Container Apps](screenshots/06-container-env.png)
- ![Capture d’écran - Container App Addok](screenshots/07-addok-app.png)
- ![Capture d’écran - Container App Addok - 2](screenshots/07-addok-app-2.png)
- ![Capture d’écran - Container App Addok - ingress](screenshots/07-addok-app-3.png)
---

## 8. Ajouter le conteneur Redis (`addok-redis`) dans la même Container App

- Ajoutez le conteneur `etalab/addok-redis`. Aller dans le Container `addokapp`, `Containers`, `Créer un nouveau container`. 
- Configurez les probes sur le port 6379.
- Montez le volume Azure File Share sur `/data`.
- ![Capture d’écran - Container App Redis](screenshots/08-redis-app.png)
---

## 10. Ajouter les Azure Files à l'environment

- Recuperer l'`access key` du Storage Account 
- Allez dans l'environement Container Apps
- Allez dans `Azure Files`
- Ajouter SMB
   - `addokfileshare` Read 
   - `addoklogfileshare` Read Write
- ![Capture d’écran - Access Key](screenshots/09-access-key.png)
- ![Capture d’écran - Files Key](screenshots/09-env-file.png)

## 9. Configurer le scaling et les ressources

- Définissez les ressources CPU/mémoire pour chaque conteneur.
- Définissez le nombre de réplicas min/max.
- ![Capture d’écran - Scaling](screenshots/09-scaling.png)

---

## 10. Récupérer l’URL publique de l’application

- Une fois déployée, l’URL publique (FQDN) sera affichée dans la configuration d’ingress de la Container App.
- ![Capture d’écran - FQDN](screenshots/10-fqdn.png)

---

## Chargement des données dans Azure File Share via le portail Azure

1. **Téléchargez le fichier de données**
   - Si vous ne l’avez pas déjà, téléchargez le fichier [`addok-france-bundle.zip`](addok-france-bundle.zip) depuis :  
     [https://adresse.data.gouv.fr/data/ban/adresses/latest/addok/addok-france-bundle.zip](https://adresse.data.gouv.fr/data/ban/adresses/latest/addok/addok-france-bundle.zip)

2. **Décompressez le fichier**
   - Décompressez l’archive dans un dossier local nommé `addok-data`.
   - Vous obtiendrez au moins les fichiers suivants :
     - `addok.conf`
     - `dump.rdb`
     - `addok.db`

3. **Accédez à votre compte de stockage dans le portail Azure**
   - Ouvrez le portail Azure.
   - Accédez à votre **Compte de stockage** utilisé pour Addok.
   - Dans le menu, cliquez sur **Partages de fichiers** puis sur le partage `addokfileshare`.

4. **Créez les dossiers nécessaires**
   - Dans le partage de fichiers, créez les dossiers suivants si besoin :
     - `addok`
     - `redis`
     - `data`

5. **Chargez les fichiers dans les bons dossiers**
   - Dans le dossier `addok`, chargez le fichier `addok.conf`.
   - Dans le dossier `redis`, chargez le fichier `dump.rdb`.
   - Dans le dossier `data`, chargez le fichier `addok.db`.

   *(Utilisez le bouton "Charger" dans l’interface Azure pour chaque fichier.)*

6. **Vérifiez que tous les fichiers sont bien présents dans les bons dossiers.**



