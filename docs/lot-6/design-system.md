# Design system — Lot 6

NexaFiles adopte une identité vert minéral centrée sur la clarté, avec violet réservé à la lecture et quelques couleurs sémantiques pour les formats. Les modes clair et sombre utilisent des fonds distincts des surfaces et des cartes.

Les constantes utiles sont centralisées dans `design_tokens.dart` : espacements, rayons, mouvements et couleurs. Les cartes utilisent un rayon de 18 px, les bottom sheets 24 px et les transitions visées restent entre 160 et 220 ms.

Material 3 fournit NavigationBar, Card, ActionChip, FAB, BottomSheet et boutons. Les cibles tactiles restent celles des composants Android standards. Les actions iconiques disposent de tooltips et les accès rapides exposent des semantics de bouton.
