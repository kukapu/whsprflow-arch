"""Exercise Linux overrides, native-platform preservation and fail-closed patches."""

import json
import pathlib
import re
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class PatchFallbacks(unittest.TestCase):
    def test_hub_detection_accepts_new_title_without_matching_other_windows(self):
        wrapper = (ROOT / "bin" / "wispr-flow").read_text()
        match = re.search(r"hub_address\(\) \{.*?jq -r '(.*?)'", wrapper, re.S)
        assert match is not None
        query = match.group(1)
        unrelated = [
            {"class": "wispr-flow", "title": title, "address": "wrong"}
            for title in ("Status", "Context Menu", "Scratchpad", "Wispr Flow Notes")
        ] + [{"class": "other-app", "title": "Wispr Flow", "address": "wrong"}]
        for title in ("Hub", "Flow Hub", "Wispr Flow"):
            for field in ("title", "initialTitle"):
                clients = unrelated + [
                    {"class": "wispr-flow", field: title, "address": "hub"}
                ]
                result = subprocess.run(
                    ["jq", "-r", query],
                    input=json.dumps(clients),
                    check=True,
                    capture_output=True,
                    text=True,
                )
                self.assertEqual(result.stdout.strip(), "hub")
        result = subprocess.run(
            ["jq", "-r", query],
            input=json.dumps(unrelated),
            check=True,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.stdout, "")

    def patch(self, script, source):
        with tempfile.TemporaryDirectory() as directory:
            bundle = pathlib.Path(directory) / "index.js"
            bundle.write_text(source)
            command = ["bash", str(ROOT / "patches" / script), str(bundle)]
            subprocess.run(command, check=True, capture_output=True, text=True)
            patched = bundle.read_text()
            subprocess.run(command, check=True, capture_output=True, text=True)
            self.assertEqual(bundle.read_text(), patched, "patch must be idempotent")
            return patched

    def evaluate(self, source, setup, assertions):
        subprocess.run(
            [
                "node",
                "-e",
                'const assert=require("node:assert/strict");'
                + setup
                + source
                + assertions,
            ],
            check=True,
            capture_output=True,
            text=True,
        )

    def test_helper_resolver_preserves_non_linux_path(self):
        source = (
            "function resolve(){const target=(0,resolver.path)();"
            "if(!fs().existsSync(target))return logger().error("
            '"Helper service script path not found");return target;}'
        )
        patched = self.patch("helper-resolver-fallback.sh", source)
        for platform, expected in (
            ("linux", "/resources/Release/wispr-flow-linux-helper"),
            ("win32", "original"),
            ("darwin", "original"),
        ):
            setup = (
                f'const process={{platform:"{platform}",resourcesPath:"/resources"}};'
                'const logs=[],resolver={path:()=>"original"};'
                "const logger=()=>({info:x=>logs.push(x),error:x=>{throw Error(x)}});"
                'const fs=()=>({existsSync:x=>typeof x==="string"});'
            )
            self.evaluate(
                patched,
                setup,
                f'assert.equal(resolve(),"{expected}");'
                f"assert.equal(logs.length,{1 if platform == 'linux' else 0});",
            )

    def test_environment_survives_identifier_changes(self):
        for symbol in ("f", "b", "$telemetry"):
            source = (
                f"const factory=()=>({{sentryDSN:{symbol}.kL,environment:{symbol}.M0,"
                f"segmentWriteKey:{symbol}.yj,postHogProjectKey:{symbol}.jd,"
                f'sentryLocalDebug:{symbol}.iP?"true":"",developmentFileLogging:"false"}});'
            )
            patched = self.patch("helper-env-fallback.sh", source)
            setup = (
                'const process={env:{WAYLAND_DISPLAY:"wayland-test",'
                'XDG_RUNTIME_DIR:"/run/test",sentryDSN:"wrong"}};'
                f'const {symbol}={{kL:"dsn",M0:"production",yj:"segment",jd:"posthog",iP:false}};'
            )
            self.evaluate(
                patched,
                setup,
                'assert.equal(factory().WAYLAND_DISPLAY,"wayland-test");'
                'assert.equal(factory().XDG_RUNTIME_DIR,"/run/test");'
                'assert.equal(factory().sentryDSN,"dsn");',
            )

    def test_window_config_is_scoped_to_linux_and_windows(self):
        source = (
            'const config={};"win32"===process.platform&&Object.assign(config,'
            '{titleBarStyle:"hidden",frame:!1,autoHideMenuBar:!0});'
        )
        patched = self.patch("window-frame-fallback.sh", source)
        for platform in ("linux", "win32", "darwin"):
            expected = (
                "{}"
                if platform == "darwin"
                else ('{titleBarStyle:"hidden",frame:false,autoHideMenuBar:true}')
            )
            self.evaluate(
                patched,
                f'const process={{platform:"{platform}"}};',
                f"assert.deepEqual(config,{expected});",
            )

    def test_unknown_bundle_is_rejected_without_modification(self):
        for script in (
            "helper-resolver-fallback.sh",
            "helper-env-fallback.sh",
            "window-frame-fallback.sh",
            "linux-runtime-fixes.sh",
        ):
            with tempfile.TemporaryDirectory() as directory:
                bundle = pathlib.Path(directory) / "index.js"
                source = 'console.log("unsupported bundle");'
                bundle.write_text(source)
                result = subprocess.run(
                    ["bash", str(ROOT / "patches" / script), str(bundle)],
                    capture_output=True,
                    text=True,
                )
                self.assertNotEqual(result.returncode, 0, script)
                self.assertEqual(bundle.read_text(), source, script)


if __name__ == "__main__":
    unittest.main()
