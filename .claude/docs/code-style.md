# Code Style, Conventions & Git Workflow

## File Organization

- Screens go in `Flipcash/Core/Screens/`
- ViewModels are colocated with their screens
- Models go in `FlipcashCore/Sources/FlipcashCore/Models/`
- Database models go in `Flipcash/Core/Controllers/Database/Models/`

## Naming Conventions

- ViewModels: `{Screen}ViewModel` (e.g., `GiveViewModel`)
- Screens: `{Name}Screen` (e.g., `ScanScreen`)
- Controllers: `{Domain}Controller` (e.g., `RatesController`)

## Import Order

```swift
import SwiftUI       // System frameworks first
import FlipcashCore  // Then internal packages
import FlipcashUI
```

## Avoid Over-Engineering

- Don't add features beyond what was asked
- Don't add error handling for impossible scenarios
- Don't create abstractions for one-time operations
- Don't add comments to code you didn't change
- Three similar lines of code is better than a premature abstraction

## Git & Workflow

### Commit Messages

```
<type>: <short description>

<optional body explaining why>
```

Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`

### Before Committing

1. Code compiles without errors and no new warnings: `./Scripts/build.sh`
2. Targeted tests pass for the changed areas: `./Scripts/test.sh <your-suites>` — the user runs the full `AllTargets` suite themselves before approving the commit
3. Review changes with `git diff`
4. Switch statements are exhaustive (no unnecessary `default` cases)
5. Changes are minimal and focused on the task
