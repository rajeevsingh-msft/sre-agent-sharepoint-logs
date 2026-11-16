# Next steps

[Project README](../Readme.md) | [Validation status](./SRE-Agent-Testing.md#validation-status)

**Updated:** October 29, 2026. This is a roadmap, not a second setup checklist or authorization to change Azure.

## Contents

- [Before publishing](#before-publishing)
- [Before each customer demonstration](#before-each-customer-demonstration)
- [Future synthetic ULS version](#future-synthetic-uls-version)
- [Real SharePoint support](#real-sharepoint-support)

## Before publishing

- Use an owner-approved sharing destination and retain the [MIT License](../LICENSE), including its copyright and permission notice. Confirm any additional organizational IP/redistribution requirements before sharing.
- Review the exact outgoing files, including screenshots; exclude private notes, azd state and raw evidence.
- Validate the extracted customer ZIP using the [existing checks](../Readme.md#validation) and all three Bicep templates.
- Record compatibility skips as skips. Do not label local/mock success production-ready.
- Exclude Git history, local operator notes, local instructions, account state and generated output. Do not send a ZIP of the unfiltered working directory.

## Before each customer demonstration

- Verify the approved target, effective UAMI access, Review mode and matching reader/data hashes.
- Follow [agent testing](./SRE-Agent-Testing.md); capture fresh positive/negative results privately.
- For richer analysis, retrieve the full [incident page set](./Incident-Demo.md#run-an-actual-sre-agent-investigation).
- Verify configured skill activation separately; a successful bootstrap does not prove reusable-skill acceptance.
- Keep the working lab unchanged unless a reviewed upgrade is required. Do not redeploy to repeat documentation.

## Future synthetic ULS version

**Planned, not implemented:** A separate versioned multi-file dataset and reader.

- Representative columns and incidents spanning simulated servers/files.
- Allowlisted directory, bounded correlation/time selection and explicit coverage.
- Safe continuation, source references and duplicate detection.
- Tests for rotation, encoding, continuation records, long messages and volume limits.

Preserve v1 and its smoke tests. Review scope and obtain approval before implementation or guest installation; no SharePoint installation is inherently required for synthetic data.

## Real SharePoint support

Production support is a separate engineering and authorization decision:

1. Obtain approved, sanitized real samples and source/retention requirements.
2. Validate schema, encoding, timestamps, rotation, active-file sharing and multi-server coverage.
3. Design source-side redaction, identity/least privilege, audit, retention and failure handling.
4. Compare bounded direct retrieval with centralized queryable logging for the actual workload.
5. Repeat manual, agent, safety and performance acceptance under approved conditions.

Renaming TSV files or removing reader limits does not establish ULS compatibility. Do not point the current demo reader at production folders.
