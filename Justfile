run:
    xcodebuild -project Nab.xcodeproj -scheme Nab -configuration Debug build
    open ~/Library/Developer/Xcode/DerivedData/Nab-*/Build/Products/Debug/Nab.app

fmt:
    xcrun swift-format format -i -r Nab/

lint:
    xcrun swift-format lint -r Nab/
