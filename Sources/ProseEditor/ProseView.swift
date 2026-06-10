#if canImport(UIKit)
import CoreGraphics
import CoreText
import ProseModel
import UIKit

public final class ProseView: UIView {
    public var document: Document {
        didSet {
            relayout()
            setNeedsDisplay()
        }
    }

    private let engine: LayoutEngine
    private var layoutBox: LayoutBox?

    public init(document: Document, schema: Schema = .slice1) {
        self.document = document
        self.engine = LayoutEngine(schema: schema)
        super.init(frame: .zero)
        backgroundColor = .systemBackground
        contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        relayout()
    }

    public override func draw(_ rect: CGRect) {
        guard let layoutBox else { return }
        UIColor.label.setFill()
        for box in layoutBox.children {
            draw(block: box)
        }
    }

    private func relayout() {
        guard bounds.width > 0 else { return }
        layoutBox = try? engine.layout(document, width: bounds.width)
    }

    private func draw(block: LayoutBox) {
        let text = block.lineFragments.first?.text ?? ""
        let size: CGFloat = block.node.type == "heading" ? 28 : 17
        let weight: UIFont.Weight = block.node.type == "heading" ? .bold : .regular
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: UIColor.label,
        ]
        text.draw(in: block.frame, withAttributes: attributes)
    }
}
#endif
