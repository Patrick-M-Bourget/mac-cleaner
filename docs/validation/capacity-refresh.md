# Startup capacity refresh — #49

Contract locked October24,2026 in [CAPACITY-REFRESH](../CAPACITY-REFRESH.md). Implementation and public/native qualification pending. Existing approved UI journeys remain the UI test seam; controlled service boundary explicitly approved by user on October24. No tests or native evidence are claimed by this lock.


## First public UI tracer

Test-only agent `ab42ba9`, root `8941c41`: explicit capacity refresh exists separately from Scan again and preserves Overview coverage/navigation/empty plan and fixed window. Guarded missing-action failure captures and returns promptly. Local build-for-testing passes. Production is unchanged. Hosted behavioral red `40083724345` at `8941c41` fails at line16 on the missing capacity-only refresh action (15.030seconds), as intended. Local/native app compilation and existing Core136 (131SwiftTesting+5XCTest) pass. The user subsequently approved the controlled-reading/clock service boundary; service-first TDD resumes from this observed UI red.
