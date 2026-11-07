"""Unit tests of deployment gates and rendering; no Azure/GitHub/network operations."""

import copy
import importlib.util
import io
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


gate = load("check_deployment")
renderer = load("render_kubernetes")
smoke = load("smoke_aks")


class DeploymentTests(unittest.TestCase):
    def setUp(self):
        self.environment = {
            "can_admins_bypass": False,
            "deployment_branch_policy": {"custom_branch_policies": True},
            "protection_rules": [{"type": "required_reviewers", "prevent_self_review": True,
                                  "reviewers": [{"type": "User", "reviewer": {"id": 1}}]}],
        }
        self.policies = {"branch_policies": [{"name": "main", "type": "branch"}]}
        self.sha = "a" * 40
        self.source = {"GITHUB_REPOSITORY": gate.REPOSITORY,
                       "GITHUB_EVENT_NAME": "workflow_dispatch",
                       "GITHUB_REF": "refs/heads/main", "GITHUB_SHA": self.sha,
                       "SOURCE_SHA": self.sha}

    def test_valid_gate(self):
        gate.validate_gate(self.environment, self.policies)

    def test_fail_closed_gate(self):
        for key, value in (("can_admins_bypass", True), ("can_admins_bypass", None),
                           ("protection_rules", []), ("deployment_branch_policy", {})):
            with self.subTest(key=key, value=value):
                environment = copy.deepcopy(self.environment)
                environment[key] = value
                with self.assertRaises(ValueError):
                    gate.validate_gate(environment, self.policies)

    def test_no_self_review(self):
        self.environment["protection_rules"][0]["prevent_self_review"] = False
        with self.assertRaises(ValueError):
            gate.validate_gate(self.environment, self.policies)

    def test_no_tag_or_wildcard_or_extra_branch(self):
        for branches in ([], [{"name": "*", "type": "branch"}],
                         [{"name": "main", "type": "tag"}],
                         self.policies["branch_policies"] * 2):
            with self.subTest(branches=branches), self.assertRaises(ValueError):
                gate.validate_gate(self.environment, {"branch_policies": branches})

    def test_valid_source(self):
        gate.validate_source(self.source, self.sha)

    def test_untrusted_source(self):
        for key, value in (("GITHUB_EVENT_NAME", "pull_request"), ("GITHUB_REF", "refs/heads/demo-complete"),
                           ("GITHUB_REPOSITORY", "fork/repo"), ("SOURCE_SHA", "b" * 40),
                           ("GITHUB_SHA", "short")):
            source = dict(self.source)
            source[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                gate.validate_source(source, self.sha)

    def test_stale_main(self):
        with self.assertRaises(ValueError):
            gate.validate_source(self.source, "b" * 40)

    def test_render_digest_and_namespace(self):
        values = {"AKS_NAMESPACE": "synthetic-demo", "ACR_LOGIN_SERVER": "synthetic.azurecr.io"}
        for name, key in renderer.IMAGE_KEYS.items():
            values[key] = f"synthetic.azurecr.io/showcase/{name}@sha256:" + "a" * 64
        document = renderer.render(values)
        self.assertEqual(len(document["items"]), 6)
        self.assertTrue(all(item["metadata"]["namespace"] == "synthetic-demo"
                            for item in document["items"]))
        for invalid in ("synthetic.azurecr.io/showcase/emi:latest",
                        "untrusted.azurecr.io/showcase/emi@sha256:" + "a" * 64,
                        "synthetic.azurecr.io/showcase/emi@sha256:short"):
            with self.subTest(image=invalid), self.assertRaises(ValueError):
                renderer.render({**values, "EMI_IMAGE": invalid})

    def test_render_requires_valid_namespace(self):
        with self.assertRaises(ValueError):
            renderer.render({"AKS_NAMESPACE": "bad;command"})

    def test_targets_missing(self):
        with self.assertRaises(ValueError):
            gate.validate_targets({})

    def test_explicit_target_validation(self):
        values = {key: f"{index:08x}-0000-0000-0000-000000000001" for index, key in enumerate(
            ("AZURE_BUILD_CLIENT_ID", "AZURE_DEPLOY_CLIENT_ID", "AZURE_TENANT_ID", "AZURE_SUBSCRIPTION_ID"), 1)}
        values.update(ACR_NAME="synthetic", AKS_RESOURCE_GROUP="synthetic-rg",
                      AKS_CLUSTER_NAME="synthetic-cluster", AKS_NAMESPACE="synthetic-demo",
                      AKS_RUNNER_LABELS_JSON='["self-hosted","Linux","synthetic-network"]')
        gate.validate_targets(values)
        for key, value in (("ACR_NAME", "bad;command"), ("AKS_NAMESPACE", ""),
                           ("AZURE_TENANT_ID", "bad"), ("AKS_RUNNER_LABELS_JSON", '["windows-latest"]'),
                           ("ACR_RUNNER_LABELS_JSON", "{}"),
                           ("AZURE_DEPLOY_CLIENT_ID", values["AZURE_BUILD_CLIENT_ID"])):
            with self.subTest(key=key), self.assertRaises(ValueError):
                gate.validate_targets({**values, key: value})

    def test_smoke_uses_loopback_and_cleans_only_its_process(self):
        process = Mock()
        process.poll.return_value = None

        def start(arguments, **kwargs):
            self.assertEqual(arguments, [
                "kubectl", "--namespace", "synthetic-demo", "port-forward",
                "--address", "127.0.0.1", "service/fx", ":8080"])
            kwargs["stdout"].write("Forwarding from 127.0.0.1:45678 -> 8080\n")
            kwargs["stdout"].flush()
            return process

        with patch.object(smoke.subprocess, "Popen", side_effect=start), patch.object(
                smoke.urllib.request, "urlopen",
                side_effect=[io.StringIO('{"status":"ok"}'),
                             io.StringIO('{"converted_amount":"8800.00"}')]) as request:
            smoke.check_service("synthetic-demo", "fx")
        self.assertEqual(request.call_args_list[0].args[0], "http://127.0.0.1:45678/health")
        process.terminate.assert_called_once()

    def test_failed_smoke_still_cleans_owned_process(self):
        process = Mock()
        process.poll.return_value = 1
        with patch.object(smoke.subprocess, "Popen", return_value=process), self.assertRaises(RuntimeError):
            smoke.check_service("synthetic-demo", "fx")
        process.terminate.assert_called_once()


if __name__ == "__main__":
    unittest.main()
