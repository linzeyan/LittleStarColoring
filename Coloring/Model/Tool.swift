enum BrushKind: String, CaseIterable, Sendable {
    case crayon, marker, watercolor, oil, ink, airbrush, rainbow, glitter, stars, puffy, chalk, pencil
}

enum Tool: Hashable, Sendable {
    case bucket
    case brush(BrushKind)
    case stamp
    case eraser
}
