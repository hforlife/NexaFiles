# EPUB — Lot 4

Le moteur V1 final utilise le décodeur ZIP existant pour `container.xml`, l'OPF, le manifeste et le spine, puis rend chaque ressource XHTML dans une Android WebView native. Ce choix conserve le CSS EPUB, les images et les polices locales sans dépendre de `pub get`.

Fonctions : sommaire issu du spine, navigation, recherche par chapitre, progression stable, reprise, signets, zoom typographique et thèmes clair/sombre/sépia. Titre, auteur et couverture OPF sont lus lorsque présents. La couverture est réduite à 300 px dans `CacheManager/covers`.

Le locator final est `href:<ressource du spine>` avec chapitre de secours. Il reste stable face aux changements typographiques, mais ce n'est pas un CFI standard. Les anciennes progressions `chapter:N` restent lisibles et sont remplacées au prochain enregistrement.

Politique WebView : JavaScript et DOM storage désactivés, réseau bloqué, `content://` interdit, accès universel depuis `file://` interdit, requêtes limitées à la racine extraite canonique et Safe Browsing activé lorsque disponible. Les liens externes sont bloqués dans la V1.

Limites V1 : pas de DRM, de CFI standard, de liens externes intégrés ni de restauration intra-chapitre.
