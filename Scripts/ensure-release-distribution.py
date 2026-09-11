"""Reuse or dispatch one exact-commit distribution; never publish or approve it."""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import time
import urllib.request

ACTIVE = {"queued", "waiting", "in_progress", "requested", "pending"}


class DistributionError(RuntimeError):
    pass


class GitHub:
    def __init__(self, repository, token):
        self.root = f"https://api.github.com/repos/{repository}"
        self.headers = {"Authorization": f"Bearer {token}",
                        "Accept": "application/vnd.github+json",
                        "X-GitHub-Api-Version": "2022-11-28"}

    def request(self, path, data=None):
        request = urllib.request.Request(
            self.root + path, headers=self.headers,
            data=None if data is None else json.dumps(data).encode())
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response) if response.status != 204 else None

    def runs(self):
        runs = []
        for page in range(1, 11):
            document = self.request(
                f"/actions/workflows/release.yml/runs?event=workflow_dispatch&branch=main&per_page=100&page={page}")
            batch = document["workflow_runs"]
            runs.extend(batch)
            if len(batch) < 100:
                return runs
        raise DistributionError("Distribution history exceeds bounded search; refusing dispatch")

    def run(self, run_id):
        return self.request(f"/actions/runs/{run_id}")

    def artifacts(self, run_id):
        document = self.request(f"/actions/runs/{run_id}/artifacts?per_page=100")
        if document["total_count"] > 100:
            raise DistributionError("Artifact listing exceeds bounded search")
        return document["artifacts"]

    def main_sha(self):
        return self.request("/git/ref/heads/main")["object"]["sha"]

    def dispatch(self):
        self.request("/actions/workflows/release.yml/dispatches", {"ref": "main"})


def matches(run, sha, repository):
    return (run.get("head_sha") == sha and run.get("head_branch") == "main"
            and run.get("event") == "workflow_dispatch"
            and run.get("path") == ".github/workflows/release.yml"
            and run.get("repository", {}).get("full_name", "").lower() == repository.lower()
            and type(run.get("id")) is int and run["id"] > 0
            and type(run.get("run_attempt")) is int and run["run_attempt"] > 0)


def has_artifact(api, run, sha):
    matches = [a for a in api.artifacts(run["id"])
               if a.get("name") == f"pkglift-macos-arm64-{sha}"
               and a.get("expired") is False and a.get("size_in_bytes", 0) > 0]
    if len(matches) > 1:
        raise DistributionError("Ambiguous distribution artifacts")
    return len(matches) == 1


def ensure_distribution(api, sha, repository, *, clock=time.monotonic,
                        sleep=time.sleep, timeout=9000):
    deadline = clock() + timeout
    runs = api.runs()
    baseline = {r["id"] for r in runs}
    candidates = sorted((r for r in runs if matches(r, sha, repository)),
                        key=lambda r: r["id"], reverse=True)
    selected = None
    # An in-flight validation takes precedence over a historic success.
    active = [r for r in candidates if r.get("status") in ACTIVE]
    if active:
        selected = active[0]
    else:
        for run in candidates:
            if run.get("status") == "completed" and run.get("conclusion") == "success":
                if has_artifact(api, run, sha):
                    selected = run
                    break
    if selected is None:
        if api.main_sha() != sha:
            raise DistributionError("Main moved; refusing to dispatch another commit")
        api.dispatch()  # Never automatically retry an uncertain POST.
    previous = None
    while clock() < deadline:
        if selected is None:
            fresh = [r for r in api.runs() if r["id"] not in baseline
                     and matches(r, sha, repository)]
            if len(fresh) > 1:
                raise DistributionError("Multiple new distribution runs; refusing ambiguous selection")
            if fresh:
                selected = fresh[0]
        if selected is not None:
            run = api.run(selected["id"])
            if (run.get("id") != selected["id"]
                    or run.get("run_attempt") != selected["run_attempt"]
                    or not matches(run, sha, repository)):
                raise DistributionError("Selected distribution identity changed")
            state = (run.get("status"), run.get("conclusion"))
            if state != previous:
                print(f"Distribution workflow {run['id']}: {state}", flush=True)
                previous = state
            if run.get("status") == "completed":
                if run.get("conclusion") != "success":
                    raise DistributionError("Selected distribution did not succeed")
                if not has_artifact(api, run, sha):
                    raise DistributionError("Successful distribution has no live expected artifact")
                return run["id"]
            if run.get("status") not in ACTIVE:
                raise DistributionError("Unknown distribution status")
        sleep(15)
    raise DistributionError("Timed out waiting for signed distribution validation")


def main():
    repository = os.environ["GITHUB_REPOSITORY"]
    sha = os.environ["GITHUB_SHA"]
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise DistributionError("Invalid repository")
    if not re.fullmatch(r"[0-9a-f]{40}", sha):
        raise DistributionError("Invalid commit")
    run_id = ensure_distribution(GitHub(repository, os.environ["GITHUB_TOKEN"]), sha, repository)
    url = f"https://github.com/{repository}/actions/runs/{run_id}"
    with Path(os.environ["GITHUB_OUTPUT"]).open("a") as output:
        output.write(f"run_id={run_id}\nrun_url={url}\n")
    with Path(os.environ["GITHUB_STEP_SUMMARY"]).open("a") as summary:
        summary.write(f"\n### Signed distribution validation\n\n- Workflow run: {url}\n- Conclusion: `success`\n")


if __name__ == "__main__":
    main()
