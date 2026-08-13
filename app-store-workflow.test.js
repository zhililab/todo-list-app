import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const workflowPath = new URL('./.github/workflows/app-store-release.yml', import.meta.url);

test('App Store workflow uses the supported stable Apple build environment', async () => {
  const workflow = await readFile(workflowPath, 'utf8');

  assert.match(workflow, /workflow_dispatch:/);
  assert.match(workflow, /runs-on:\s*macos-26/);
  assert.match(workflow, /Xcode_26\.6\.app/);
  assert.match(workflow, /BuildMachineOSBuild/);
  assert.match(workflow, /DTXcodeBuild/);
  assert.match(workflow, /DTSDKBuild/);
  assert.match(workflow, /CURRENT_PROJECT_VERSION=4/);
});

test('App Store workflow keeps credentials in secrets and cleans temporary signing state', async () => {
  const workflow = await readFile(workflowPath, 'utf8');

  for (const secret of [
    'APP_STORE_CONNECT_KEY_ID',
    'APP_STORE_CONNECT_ISSUER_ID',
    'APP_STORE_CONNECT_PRIVATE_KEY_BASE64',
    'APP_STORE_CERTIFICATE_BASE64',
    'APP_STORE_CERTIFICATE_PASSWORD',
    'APP_STORE_PROVISIONING_PROFILE_BASE64',
  ]) {
    assert.match(workflow, new RegExp(`secrets\\.${secret}`));
  }

  assert.match(workflow, /security delete-keychain/);
  assert.match(workflow, /rm -f "\$AUTH_KEY_PATH"/);
  assert.match(workflow, /if:\s*always\(\)/);
  assert.doesNotMatch(workflow, /AuthKey_[A-Z0-9]+\.p8/);
});

test('App Store workflow uses the dedicated distribution profile without Cloud Signing', async () => {
  const workflow = await readFile(workflowPath, 'utf8');

  assert.match(workflow, /Install App Store provisioning profile/);
  assert.match(workflow, /APP_STORE_PROVISIONING_PROFILE_BASE64/);
  assert.match(workflow, /CODE_SIGN_STYLE=Manual/);
  assert.match(workflow, /PROVISIONING_PROFILE_SPECIFIER="Todo Native App Store Build 4"/);
  assert.match(workflow, /<key>provisioningProfiles<\/key>/);
  assert.match(workflow, /<key>com\.zhili\.todo-native<\/key>\s*<string>Todo Native App Store Build 4<\/string>/);
  assert.match(workflow, /rm -f "\$PROVISIONING_PROFILE_PATH"/);
});

test('App Store workflow uploads only after archive provenance validation', async () => {
  const workflow = await readFile(workflowPath, 'utf8');
  const validation = workflow.indexOf('Validate archive provenance');
  const upload = workflow.indexOf('Upload Build 4 to App Store Connect');

  assert.ok(validation >= 0, 'archive provenance validation step is required');
  assert.ok(upload > validation, 'upload must happen after provenance validation');
  assert.match(workflow, /destination<\/key>\s*<string>upload<\/string>/);
  assert.match(workflow, /manageAppVersionAndBuildNumber<\/key>\s*<false\/>/);
});

test('App Store workflow initializes runner paths at runtime and resolves the archived app once', async () => {
  const workflow = await readFile(workflowPath, 'utf8');

  assert.doesNotMatch(
    workflow,
    /^\s{6}[A-Z_]+:\s*\$\{\{\s*runner\./m,
    'runner context is not available in a job-level env block',
  );
  assert.match(workflow, /AUTH_KEY_PATH=\$RUNNER_TEMP\/app-store-connect\/AuthKey\.p8/);
  assert.match(workflow, />> "\$GITHUB_ENV"/);
  assert.match(workflow, /APP_PLIST="\$ARCHIVE_PATH\/Products\/\$APP_RELATIVE_PATH\/Info\.plist"/);
  assert.match(workflow, /BuildMachineOSBuild' "\$APP_PLIST"/);
  assert.doesNotMatch(workflow, /BuildMachineOSBuild' "\$ARCHIVE_PATH\/Info\.plist"/);
  assert.doesNotMatch(workflow, /Products\/Applications\/\$APP_RELATIVE_PATH/);
});
