import AppKit
import Testing
@testable import CurrentFeature

@Test func timelineItemsFitDuringInitialMountAndResize() {
    for width in [0.0, 1, 40, 80, 591, 900, 1200] {
        let item = TimelineLayoutMetrics.itemWidth(availableWidth: width)
        let inset = TimelineLayoutMetrics.horizontalInset(availableWidth: width)
        #expect(item > 0)
        #expect(inset >= 0)
        #expect(item + inset * 2 <= max(1, width))
    }
}

@Test @MainActor func columnLayoutRebuildsAfterContextInvalidationResizeAndRowChanges() {
    let source = ColumnLayoutFixture()
    let collection = NSCollectionView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
    let layout = TimelineColumnLayout()
    collection.collectionViewLayout = layout
    collection.dataSource = source
    collection.delegate = source
    collection.reloadData()
    layout.invalidateLayout()
    layout.prepare()
    let third = IndexPath(item: 2, section: 0)
    let oldThirdY = layout.layoutAttributesForItem(at: third)!.frame.minY

    source.heights[1] += 100
    layout.invalidateLayout(with: NSCollectionViewLayoutInvalidationContext())
    layout.prepare()
    #expect(layout.layoutAttributesForItem(at: third)!.frame.minY == oldThirdY + 100)

    collection.setFrameSize(NSSize(width: 591, height: 700))
    layout.invalidateLayout(with: NSCollectionViewLayoutInvalidationContext())
    layout.prepare()
    for index in source.heights.indices {
        let frame = layout.layoutAttributesForItem(at: IndexPath(item: index, section: 0))!.frame
        #expect(frame.minX >= 0 && frame.maxX <= collection.bounds.width)
        #expect(frame.width == TimelineLayoutMetrics.itemWidth(availableWidth: 591))
    }
    #expect(!layout.shouldInvalidateLayout(forBoundsChange: NSRect(x: 0, y: 100, width: 591, height: 700)))

    source.heights.insert(60, at: 1)
    source.heights.removeLast()
    collection.reloadData()
    layout.invalidateLayout()
    layout.prepare()
    let frames = source.heights.indices.map { layout.layoutAttributesForItem(at: IndexPath(item: $0, section: 0))!.frame }
    for index in 1..<frames.count { #expect(frames[index].minY == frames[index - 1].maxY) }
    #expect(frames.map(\.height) == source.heights)
    let visible = layout.layoutAttributesForElements(in: frames[1].insetBy(dx: 1, dy: 1))
    #expect(visible.map(\.indexPath) == [IndexPath(item: 1, section: 0)])
}

@MainActor private final class ColumnLayoutFixture: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout {
    var heights: [CGFloat] = [40, 80, 120]

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { heights.count }
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = NSCollectionViewItem()
        item.view = NSView()
        return item
    }
    func collectionView(_ collectionView: NSCollectionView, layout: NSCollectionViewLayout, sizeForItemAt path: IndexPath) -> NSSize {
        NSSize(width: TimelineLayoutMetrics.itemWidth(availableWidth: collectionView.bounds.width), height: heights[path.item])
    }
    func collectionView(_ collectionView: NSCollectionView, layout: NSCollectionViewLayout, insetForSectionAt section: Int) -> NSEdgeInsets {
        TimelineLayoutMetrics.sectionInset(availableWidth: collectionView.bounds.width)
    }
}
