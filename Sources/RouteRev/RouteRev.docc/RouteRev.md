# ``RouteRev``

Add revenue-attributed analytics to an iOS 15+ or macOS 12+ app, with no package dependencies. Configure once, track screens and successful goals, and link purchases using the stable install identity.

Start with <doc:GettingStarted>. Every app passes its own first-party collector subdomain to `configure`; the package has no built-in server address.

## Topics

### Getting started

- <doc:GettingStarted>
- ``RouteRev/configure(key:endpoint:options:)``
- ``RouteRev/Options``

### Screens and goals

- ``RouteRev/screen(_:_:)``
- ``RouteRev/goal(_:_:)``
- ``RouteRev/acquisitionSurvey(_:)``
- ``AcquisitionSource``
- ``RouteRevValue``

### Identity and purchase attribution

- ``RouteRev/identify(_:)``
- ``RouteRev/reset()``
- ``RouteRev/installId``
- ``RouteRev/revenueCatAttributes``

### Delivery

- ``RouteRev/flush()``
- ``RouteRev/isEnabled``
