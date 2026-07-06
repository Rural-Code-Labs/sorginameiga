/// All translatable strings for a single language.
///
/// Maps one-to-one to the global variables defined in the legacy
/// `old_web/languajes/{esp,ing}.php` files. Plain data passed to Leaf, so it
/// is a value type conforming to `Encodable`.
struct Translation: Encodable, Sendable {
    // Header / menu
    let title: String       // $TITULO
    let aboutUs: String     // $QUIENES
    let males: String       // $MACHOS
    let females: String     // $HEMBRAS
    let puppies: String     // $CACHORROS
    let gallery: String     // $GALERIA
    let links: String       // $LINKS
    let contact: String     // $CONTACTOS
    let back: String        // $VOLVER
    let close: String       // lightbox close button (phase 9d)
    let previous: String    // lightbox previous-photo button (phase 9d)
    let next: String        // lightbox next-photo button (phase 9d)
    let pedigree: String    // dog detail: pedigree table heading

    // Footer
    let totalOf: String     // $UNTOTALDE
    let visitsSince: String // $VISITASDESDE
    let credits: String     // $CREDITOS
    let available: String   // $DISPONIBLE
    let unavailable: String // $NODISPONIBLE

    // Contact form (reserved for a later phase)
    let formTitle: String   // $F_FORMULARIO
    let formText: String    // $F_TEXTO
    let formName: String    // $F_NOMBRE
    let formEmail: String   // $F_CORREO
    let formPhone: String   // $F_TELEFONO
    let formSubject: String // $F_ASUNTO
    let formMessage: String // $F_MENSAJE
    let formSend: String    // $F_ENVIAR

    // Empty-state messages (legacy `error.php` types nocachorros / nogalerias)
    let noPuppies: String
    let noGalleries: String

    // Home page — contains HTML markup, rendered raw in the template.
    let presentation: String // $PRESENTACION
}
