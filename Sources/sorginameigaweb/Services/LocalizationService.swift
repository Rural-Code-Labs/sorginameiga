import Vapor

/// Provides the translated strings for each supported language.
///
/// Swift counterpart to the legacy `old_web/languajes/*.php` files (which
/// defined global variables per language). A single instance is created in
/// `configure(_:)` and reused across all requests.
final class LocalizationService: Sendable {
    private let spanish: Translation
    private let english: Translation

    init() {
        spanish = Translation(
            title: "Criadero Lhasa Apso",
            aboutUs: "¿Quiénes Somos?",
            males: "Machos",
            females: "Hembras",
            puppies: "Cachorros",
            gallery: "Galería Multimedia",
            links: "Links",
            contact: "Contactos",
            back: "Volver",
            close: "Cerrar",
            previous: "Anterior",
            next: "Siguiente",
            pedigree: "Pedigrí",
            totalOf: "La web ha recibido ",
            visitsSince: " visitas desde noviembre de 2013",
            credits: "Web desarrollada por Rural Code Labs",
            available: "Disponible",
            unavailable: "No Disponible",
            formTitle: "Formulario de Contacto",
            formText: "Puedes escribirnos por correo electrónico, llamarnos o contactar con nosotras vía WhatsApp.",
            formName: "Nombre",
            formEmail: "Correo",
            formPhone: "Teléfono",
            formSubject: "Asunto",
            formMessage: "Mensaje",
            formSend: "Enviar",
            noPuppies: "No hay cachorros disponibles en este momento.",
            noGalleries: "No hay galerías disponibles en este momento.",
            cookieText: "Usamos cookies de Google Analytics para medir las visitas. Puedes aceptarlas o rechazarlas.",
            cookieAccept: "Aceptar",
            cookieReject: "Rechazar",
            presentation: """
            <p>Hola:</p>
            <p>Somos Pilar Díaz y Estíbaliz Domínguez, propietarias del criadero de lhasa apso Sorgiña-Meiga. </p>
            <p>En el año 1994 nos introdujimos en este mundo de la cría y de las exposiciones de belleza con nuestros lhasas.</p>
            <p>No os vamos a dar la murga con nuestra historia como criadoras ni con la historia de nuestros perros. Os mostramos unas cuantas fotos de todos ellos y vosotros decidís: para nosotras siempre serán los mejores y los más guapos. </p>
            <p>P.D. El nombre Sorgiña-Meiga significa bruja-bruja, en euskera y en gallego. ¿Lo pilláis?</p>
            <p>Según el estándar de la raza, el carácter del lhasa es prudente y desconfiado con los extraños, aunque con los suyos es cariñoso, fiel y tranquilo. Es un perro alegre, muy seguro de sí mismo y poco ladrador, solo cuando tiene que avisar de algo extraño. </p>
            <p>Según nuestra experiencia, la gran mayoría cumple estas características, pero como siempre hay excepciones: en el criadero tenemos algunos que se van con cualquiera que les ponga una correa.</p>
            """
        )

        english = Translation(
            title: "Lhasa Apso Kennel",
            aboutUs: "About Us",
            males: "Males",
            females: "Females",
            puppies: "Puppies",
            gallery: "Multimedia Gallery",
            links: "Links",
            contact: "Contact",
            back: "Return",
            close: "Close",
            previous: "Previous",
            next: "Next",
            pedigree: "Pedigree",
            totalOf: "The website has received ",
            visitsSince: " visits since November 2013",
            credits: "Web developed by Rural Code Labs",
            available: "Available",
            unavailable: "Unavailable",
            formTitle: "Contact Form",
            formText: "You can write us by email, call us or contact us through WhatsApp.",
            formName: "Name",
            formEmail: "E-mail",
            formPhone: "Phone",
            formSubject: "Subject",
            formMessage: "Message",
            formSend: "Send",
            noPuppies: "There are no puppies available at the moment.",
            noGalleries: "There are no galleries available at the moment.",
            cookieText: "We use Google Analytics cookies to measure visits. You can accept or reject them.",
            cookieAccept: "Accept",
            cookieReject: "Reject",
            presentation: """
            <p>Hello:</p>
            <p>We are Pilar Díaz and Estíbaliz Domínguez, owners of Sorgiña-Meiga, a lhasa apso kennel.</p>
            <p>In 1994 we entered the world of breeding and dog shows with our lhasas, but we don't want to bore you with our history as breeders, nor our dogs' stories. For us they will always be the prettiest and the best.</p>
            <p>Sorgiña-Meiga means witch-witch in Galician and Basque. Got it?</p>
            <p>According to the breed standard, Lhasas are prudent and suspicious with people they don't know, although they are cheerful, loyal and quiet with the people they know. They rarely bark, only when they have to warn about something unknown.</p>
            <p>Our experience is that most of them meet these standards, but there are exceptions. In our kennel we have some dogs you could take with you just by showing a dog leash!</p>
            """
        )
    }

    /// Returns the strings for the requested language.
    func translation(for language: Language) -> Translation {
        switch language {
        case .esp: return spanish
        case .ing: return english
        }
    }
}

// MARK: - Application storage

extension Application {
    private struct LocalizationServiceKey: StorageKey {
        typealias Value = LocalizationService
    }

    /// The shared localization service. Set once in `configure(_:)`.
    var localization: LocalizationService {
        get {
            guard let service = storage[LocalizationServiceKey.self] else {
                fatalError("LocalizationService not configured. Set app.localization in configure(_:).")
            }
            return service
        }
        set { storage[LocalizationServiceKey.self] = newValue }
    }
}

extension Request {
    /// Convenience access to the shared localization service.
    var localization: LocalizationService { application.localization }
}
