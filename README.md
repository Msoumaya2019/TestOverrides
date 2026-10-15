# TestOverrides — application iOS personnelle de test

Projet Objective-C ARC sans Substrate ni dépendance tierce. Sortie attendue :
`build/TestOverrides.dylib`, Mach-O dynamique **arm64 / iPhoneOS**, iOS 13 minimum.

## État du livrable

Les sources, tests et workflow sont fournis. Le Bundle ID de test configuré par
défaut est `com.tonnom.obdtest`. Aucun IPA n'a été fourni.
L'environnement de création est Windows sans Xcode/SDK Apple : **aucune dylib n'a
été compilée ici et les tests Objective-C n'ont pas été exécutés ici**.
Le workflow doit être exécuté sur GitHub pour obtenir le binaire réel.
La compatibilité avec votre application n'a pas encore été vérifiée.

## Informations à fournir

1. Confirmer que le `CFBundleIdentifier` de votre application de test est bien
   `com.tonnom.obdtest`, ou adapter la configuration à son identifiant réel.
2. L'IPA personnel pour analyser `Payload/*.app/Info.plist`, le Mach-O principal,
   les frameworks et les chemins de réception/décodage des réponses.
3. La version iOS cible et des exemples JSON anonymisés si disponibles.

Le Bundle ID est intégré à la compilation et comparé exactement à celui du
processus au chargement et à chaque réponse. Une autre application reste inactive.
Ce contrôle est un garde-fou de test, pas une preuve de propriété ou une frontière
de sécurité contre une personne qui modifie elle-même le binaire.

## Compilation sur Mac

Installer Xcode complet, sélectionner son répertoire développeur et accepter sa
licence. Puis, à la racine de ce projet :

```bash
bash Scripts/build.sh
```

Cette commande cible `com.tonnom.obdtest`. Pour votre autre application personnelle,
définir explicitement `TARGET_BUNDLE_ID` au lancement. Le script lance les tests de
transformation sur macOS, compile séparément la dylib avec le SDK **iphoneos** et
`-target arm64-apple-ios13.0`, puis vérifie `lipo`, `vtool`, dépendances et signature.
Le programme de test macOS n'est jamais livré à la place de la dylib iOS.
Les tests macOS valident le moteur JSON ; ils ne prouvent pas le hooking sur iPhone.

## Compilation GitHub Actions

Créer un dépôt et y placer **le contenu de TestOverrides à la racine**, incluant le
dossier caché `.github`. Dans Actions, sélectionner « Build TestOverrides iPhoneOS
arm64 », puis « Run workflow » et conserver `bundle_id=com.tonnom.obdtest`.
Le runner `macos-15` utilise
son Xcode installé. À la fin d'une exécution réussie, télécharger l'artifact
`TestOverrides-ios-arm64` et en extraire `TestOverrides.dylib`.

Les builds automatiques ciblent également `com.tonnom.obdtest` par défaut.
La variable de dépôt `TARGET_BUNDLE_ID` permet de choisir un autre identifiant
pour votre application personnelle. Les vérifications de plateforme échouent si
la sortie n'est pas iOS réel. SHA256 et rapport de vérification accompagnent le binaire.
Ce workflow est fourni mais n'a pas été exécuté depuis cette session.

## Interception et limites précises

La bibliothèque se charge par constructeur et installe deux remplacements de
méthodes Objective-C sur la classe concrète de `NSURLSession.sharedSession` :

- `dataTaskWithRequest:completionHandler:`
- `dataTaskWithURL:completionHandler:`

Les implémentations originales sont conservées et appelées. Le bloc reçoit les
données HTTP complètes, les transforme si la réponse n'a pas d'erreur, puis appelle
le bloc de l'application avec les données résultantes. La requête, la réponse et
l'erreur restent celles d'origine. Aucun appel externe ni changement serveur.

| Chemin de l'application | Couverture |
| --- | --- |
| URLSession avec ces blocs, sur la classe instrumentée, puis NSJSONSerialization | Prévue, à tester sur l'IPA |
| Même chemin puis Swift JSONDecoder | Données modifiées avant le décodage, à tester |
| JSONDecoder sur des fichiers ou Data provenant d'une autre source | Non couvert |
| NSJSONSerialization hors de ces réponses réseau | Non couvert ; aucun hook du parseur |
| URLSession avec délégué et fragments `didReceiveData` | Non couvert |
| Swift async/await, Combine, Alamofire | Non garanti ; dépend du chemin interne réel |
| Sessions d'autres classes/sous-classes, uploads, downloads, WebSocket, Network.framework, moteur C/C++ | Non garanti / non couvert |

Les API Swift ne passent pas toutes par NSJSONSerialization. Un hook de ce seul
parseur n'a donc pas été choisi. Le remplacement des méthodes Foundation reste une
technique dépendante de l'implémentation iOS, susceptible de conflits avec d'autres
hooks ; il faut vérifier chaque version iOS et les sessions réellement utilisées.
Deux chemins instrumentés peuvent s'appeler mutuellement : la transformation est
idempotente. Les délais de traitement peuvent augmenter, même sans champ cible.

Le corps est parsé sans dépendre du MIME type pour accepter les serveurs qui
étiquettent mal leur JSON. Les réponses HTTP non JSON ou invalides passent sans
modification. La bibliothèque n'altère pas les en-têtes ; un Content-Length ou une
signature de contenu peut donc ne plus correspondre au corps modifié.
Les contenus chiffrés, signés, compressés encore au niveau applicatif et les flux
NDJSON ne sont pas pris en charge. Une application qui vérifie les signatures de
réponse ou impose un schéma incompatible peut rejeter ces valeurs.

## Règles JSON

Recherche récursive dans objets et tableaux, noms exacts et sensibles à la casse :

- `credits` numérique égal à 0 → 999 (pas le booléen false).
- `subscriptionType` JSON null → chaîne `ULTIMATE`.
- `subscriptionExpiration` JSON null ou chaîne `null` → `2027-10-14T23:59:59Z`.

Les valeurs déjà différentes sont préservées, conformément aux remplacements
original/nouveau demandés. Les propriétés absentes ne sont jamais ajoutées.
Sans remplacement, l'objet NSData original est renvoyé, octets identiques.
Avec remplacement, la sérialisation peut changer espaces, ordre des clés et
représentation des nombres ; les propriétés ordinaires sont préservées au sens JSON.
Les clés dupliquées et nombres nécessitant une précision au-delà de Foundation ne
permettent pas une garantie de fidélité ; fournir des exemples si cela vous concerne.
Le moteur passe sans modification les corps > 8 Mio et abandonne entièrement les
transformations au-delà de 128 niveaux, ou en cas d'erreur de parsing/sérialisation.
Cette limite est volontaire pour réduire les risques de mémoire et de récursion.

## Désactivation

Depuis le code de votre app de test ou le débogueur :

```objc
[[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"TestOverridesDisabled"];
// Réactivation : setBool:NO puis relancer l'application si les hooks n'étaient pas installés.
```

Alternative au lancement sous débogueur : variable d'environnement
`TEST_OVERRIDES_DISABLED=1`. Un environnement de lancement n'est généralement pas
configurable directement depuis ESign. Le réglage UserDefaults est relu à chaque
réponse ; les blocs déjà installés deviennent des passages directs. Si désactivée
au chargement, aucune méthode n'est remplacée, et la réactivation demande un relancement.
On peut aussi retirer la dylib et son ordre de chargement, puis signer à nouveau l'IPA.

## Intégration ESign

Fichier à injecter : **TestOverrides.dylib** issu de l'artifact iOS arm64.
Dépendances : Foundation, libobjc, libSystem et runtime Blocks système, normalement
présents sur iOS. `otool -L` donne la liste exacte de la compilation.
Aucun jailbreak, Substrate, paquet tiers, entitlement spécial ou serveur requis.

Dans votre outil ESign, ajouter la bibliothèque à votre IPA personnel avec l'option
d'injection de bibliothèque disponible dans votre version, puis signer l'ensemble
avec votre certificat/profil valides. Les intitulés et capacités ESign ne sont pas
vérifiés dans cette session. L'outil doit ajouter une commande Mach-O de chargement
résolvant le chemin effectif, copier la dylib et signer le code imbriqué puis l'app.
Le fichier déclare `@rpath/TestOverrides.dylib` comme install name : pour un placement
dans Frameworks, vérifier le rpath `@executable_path/Frameworks`, ou utiliser une
commande de chargement explicite `@executable_path/Frameworks/TestOverrides.dylib`.

La signature ad hoc créée par le build **ne permet pas à elle seule** l'installation
sur un iPhone standard. Elle doit être remplacée lors de la signature de l'IPA.
Le provisioning doit autoriser l'installation et conserver le Bundle ID attendu.
Une signature expirée/révoquée, un profil incompatible, un chemin dyld incorrect,
une protection FairPlay non résolue dans votre build personnel ou un mécanisme
d'intégrité applicatif peuvent empêcher le lancement. Utiliser un export de votre
propre build de développement ; aucun contournement de ces protections n'est fourni.
L'architecture est arm64, pas arm64e-only, pas simulateur. La compatibilité effective
du processus et de sa signature doit être testée sur l'iPhone cible.

## Logs et validation réelle

Observer la console de l'iPhone connecté depuis Console sur Mac ou Xcode en filtrant
`TestOverrides`. Le chargement affiche `library loaded`, puis les méthodes installées
ou `disabled or bundle mismatch`. Les logs info listent seulement le nom des trois
champs et le nombre de remplacements ; les logs debug signalent la détection JSON.
Pas de corps HTTP, URL, jeton, valeur privée ou message d'erreur serveur journalisé.
La visibilité des logs info/debug dépend de la configuration de collecte iOS.

Après injection : vérifier `otool -L` sur le Mach-O de l'IPA resigné, lancer l'app,
contrôler les logs d'installation des deux hooks, puis envoyer une réponse de test
et vérifier les valeurs **au point de décodage dans votre app**. Répéter avec une
nouvelle réponse, les sessions personnalisées et les API Swift utilisées. Vérifier
également la désactivation et les fonctions qui consomment les en-têtes HTTP.
Un log de chargement seul ne prouve pas l'interception. Aucun test appareil n'a été
effectué ici ; il faut l'IPA et l'appareil pour conclure à une compatibilité réelle.

## Tests automatisés

`bash Scripts/build.sh --test-only` sur Mac exécute un programme Foundation autonome.
Il vérifie les sept cas demandés, les deux formes de null pour l'expiration, les
tableaux imbriqués, la conservation des autres valeurs et le booléen false.
Le script s'arrête au premier échec ; le workflow ne publie rien si le build échoue.
Les hooks, signatures et chemins réseau nécessitent en plus les tests iOS décrits
ci-dessus. Les sources Apple de référence :

- [URLSession dataTask avec completionHandler](https://developer.apple.com/documentation/foundation/urlsession/datatask(with:completionhandler:)-e6xv)
- [Traitement des réponses URLSession](https://developer.apple.com/documentation/foundation/fetching-website-data-into-memory)
- [Combine et JSONDecoder](https://developer.apple.com/documentation/foundation/processing-url-session-data-task-results-with-combine)
