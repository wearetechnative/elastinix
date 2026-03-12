#!/usr/bin/env python3
import requests
import os
import sys
import argparse
import json
from requests.auth import HTTPBasicAuth

# === CONFIG LOADING ===
def load_config(config_file=None):
    """Load configuration from file, environment variables, or prompt user"""
    config = {}

    # Try to load from config file first
    if config_file:
        try:
            with open(config_file, 'r') as f:
                config = json.load(f)
                print(f"✅ Loaded configuration from {config_file}")
        except FileNotFoundError:
            print(f"❌ Config file not found: {config_file}")
            sys.exit(1)
        except json.JSONDecodeError as e:
            print(f"❌ Invalid JSON in config file: {e}")
            sys.exit(1)

    # Get EMAIL (from config file, env var, or prompt)
    email = config.get("email") or os.environ.get("JIRA_EMAIL")
    if not email:
        print("Warning: JIRA_EMAIL not found in config or environment.")
        print("Please set it with: export JIRA_EMAIL='your-email'")
        print("Or enter your email now (input will be visible):")
        email = input()
        if not email:
            print("Error: Email is required")
            sys.exit(1)

    # Get API token (from config file, env var, or prompt)
    api_token = config.get("api_token") or os.environ.get("JIRA_API_TOKEN")
    if not api_token:
        print("Warning: JIRA_API_TOKEN not found in config or environment.")
        print("Please set it with: export JIRA_API_TOKEN='your-token'")
        print("Or enter your API token now (input will be hidden):")
        import getpass
        api_token = getpass.getpass()
        if not api_token:
            print("Error: API token is required")
            sys.exit(1)

    # Get other config values with defaults


    remote_org = config.get("remote_org", "")
    local_org = config.get("local_org", "")
    project_key = config.get("project_key", "")
    status_mapping = config.get("status_mapping") or {}

    return {
        "email": email,
        "api_token": api_token,
        "remote_org": remote_org,
        "local_org": local_org,
        "project_key": project_key,
        "status_mapping": status_mapping
    }

# === STAP 1: Haal issues op uit themorg ===
def get_remote_issues(config, auth, headers, days=360):
    issues = []
    start_at = 0

    while True:

        # Get the total of issues
        total_url = f"https://{config['remote_org']}.atlassian.net/rest/api/3/search/approximate-count"
        payload = json.dumps({"jql": f"project={config['project_key']}"})
        response_total = requests.request("POST", total_url, data=payload, headers=headers, auth=auth)
        data_total = response_total.json()
        total = data_total["count"]

        url = f"https://{config['remote_org']}.atlassian.net/rest/api/3/search/jql"
        # Use the days parameter for the time constraint
        query = f"project={config['project_key']} AND created >= -{days}d ORDER BY created DESC"
        params = {
            "jql": query,
            "maxResults": total,
            "fields": "*all"
        }
        try:
            response = requests.get(url, headers=headers, params=params, auth=auth)
            response.raise_for_status()
            data = response.json()

            if "issues" not in data:
                print(f"Warning: No 'issues' found in response: {data}")
                break
        except requests.exceptions.RequestException as e:
            print(f"Error fetching issues from {config['remote_org']}: {e}")
            sys.exit(1)

        # Convert the JQL search results to the format expected by the rest of the code
        for result in data["issues"]:
            issue = {
                "key": result["key"],
                "fields": {
                    "summary": result["fields"]["summary"],
                    "description": result["fields"].get("description", ""),
                    "status": {
                        "name": result["fields"]["status"]["name"]
                    }
                }
            }
            issues.append(issue)

        if start_at + total >= total:
            break
        start_at += total

        # The JQL search endpoint might have different pagination behavior
        if len(data.get("results", [])) < total:
            break

    return issues


# === STAP 2: Synchroniseer issues naar lokaal project ===
def sync_issues_to_local(config, auth, headers, issues):
    for issue in issues:
        remote_key = issue["key"]
        summary = issue["fields"]["summary"]
        description = issue["fields"].get("description", "")
        remote_status = issue["fields"]["status"]["name"]

        # Zoek lokaal issue op basis van [remote_key] in summary
        search_url = f"https://{config['local_org']}.atlassian.net/rest/api/3/search/jql"
        jql = f'project = {config["project_key"]} AND summary ~ "\\"[{remote_key}]\\""'
        try:
            response = requests.get(search_url, headers=headers, params={"jql": jql, "fields": "*all"}, auth=auth)
            response.raise_for_status()
            results = response.json()
        except requests.exceptions.RequestException as e:
            print(f"Error searching for issue in {config['local_org']}: {e}")
            continue

        if results["issues"]:
            local_issue = results["issues"][0]
            local_key = local_issue["key"]
            print(f"🔄 Bijwerken: {local_key} (voor {remote_key})")

            # Description bijwerken
            update_url = f"https://{config['local_org']}.atlassian.net/rest/api/3/issue/{local_key}"
            update_payload = {"fields": {"description": description}}
            try:
                update_response = requests.put(update_url, headers=headers, auth=auth, json=update_payload)
                update_response.raise_for_status()
                print(f"✅ Description updated for {local_key}")
            except requests.exceptions.RequestException as e:
                print(f"Error updating description for {local_key}: {e}")

            # Status synchroniseren
            local_status = local_issue["fields"]["status"]["name"]
            desired_status = config['status_mapping'].get(remote_status)
            if desired_status and local_status != desired_status:
                sync_status(config, auth, headers, local_key, desired_status)
        else:
            # Issue bestaat nog niet, dus aanmaken
            print(f"➕ Aanmaken: nieuw issue voor {remote_key}")
            create_url = f"https://{config['local_org']}.atlassian.net/rest/api/3/issue"
            payload = {
                "fields": {
                    "project": {"key": config['project_key']},
                    "summary": f"[{remote_key}] {summary}",
                    "description": description,
                    "issuetype": {"name": "Task"}
                }
            }
            try:
                response = requests.post(create_url, headers=headers, auth=auth, json=payload)
                response.raise_for_status()
                print(f"✅ Aangemaakt: {response.json()['key']}")
            except requests.exceptions.RequestException as e:
                print(f"Error creating issue for {remote_key}: {e}")


# === STAP 3: Status overzetten via transition ===
def sync_status(config, auth, headers, issue_key, target_status_name):
    try:
        trans_url = f"https://{config['local_org']}.atlassian.net/rest/api/3/issue/{issue_key}/transitions"
        response = requests.get(trans_url, headers=headers, auth=auth)
        response.raise_for_status()
        transitions = response.json()["transitions"]

        matching = [t for t in transitions if t["to"]["name"].lower() == target_status_name.lower()]
        if not matching:
            print(f"⚠️ Geen overgang beschikbaar naar '{target_status_name}' voor {issue_key}")
            return

        transition_id = matching[0]["id"]
        transition_payload = {"transition": {"id": transition_id}}
        apply_url = f"https://{config['local_org']}.atlassian.net/rest/api/3/issue/{issue_key}/transitions"
        post_response = requests.post(apply_url, headers=headers, auth=auth, json=transition_payload)
        if post_response.status_code == 204:
            print(f"✅ Status gesynchroniseerd naar '{target_status_name}' voor {issue_key}")
        else:
            print(f"❌ Status-sync fout: {post_response.status_code} {post_response.text}")
    except requests.exceptions.RequestException as e:
        print(f"❌ Error synchronizing status for {issue_key}: {e}")
    except KeyError as e:
        print(f"❌ Missing data in response when synchronizing status for {issue_key}: {e}")


# === VALIDATE CONNECTION ===
def validate_connections(config, auth, headers):
    """Validate connections to both Jira instances before starting sync"""
    print(f"🔍 Validating connection to {config['remote_org']}...")
    try:
        url = f"https://{config['remote_org']}.atlassian.net/rest/api/3/myself"
        response = requests.get(url, headers=headers, auth=auth)
        print(response)
        response.raise_for_status()
        remote_user = response.json().get("displayName", "Unknown")
        print(f"✅ Connected to {config['remote_org']} as {remote_user}")
    except requests.exceptions.RequestException as e:
        print(f"❌ Failed to connect to {config['remote_org']}: {e}")
        return False

    print(f"🔍 Validating connection to {config['local_org']}...")
    try:
        url = f"https://{config['local_org']}.atlassian.net/rest/api/3/myself"
        response = requests.get(url, headers=headers, auth=auth)
        response.raise_for_status()
        local_user = response.json().get("displayName", "Unknown")
        print(f"✅ Connected to {config['local_org']} as {local_user}")
    except requests.exceptions.RequestException as e:
        print(f"❌ Failed to connect to {config['local_org']}: {e}")
        return False

    return True


# === MAIN ===
if __name__ == "__main__":
    try:
        # Parse command line arguments
        parser = argparse.ArgumentParser(description='Synchronize Jira issues between organizations')
        parser.add_argument('--config', type=str, default=None,
                            help='Path to JSON configuration file')
        parser.add_argument('--days', type=int, default=90,
                            help='Number of days to look back for issues (default: 90)')
        parser.add_argument('--dry-run', action='store_true',
                            help='Only show what would be done, without making changes')
        args = parser.parse_args()

        # Load configuration
        config = load_config(args.config)

        # Set up authentication and headers
        auth = HTTPBasicAuth(config['email'], config['api_token'])
        headers = {"Accept": "application/json", "Content-Type": "application/json"}

        print(f"🔄 Starting synchronization from {config['remote_org']} to {config['local_org']}...")
        print(f"📅 Looking back {args.days} days for issues")

        if args.dry_run:
            print("🔍 DRY RUN MODE: No changes will be made")

        if not validate_connections(config, auth, headers):
            print("❌ Connection validation failed. Exiting.")
            sys.exit(1)

        remote_issues = get_remote_issues(config, auth, headers, days=args.days)
        print(f"🔎 Gevonden {len(remote_issues)} issues in {config['remote_org']}")

        if not args.dry_run:
            sync_issues_to_local(config, auth, headers, remote_issues)
            print("✅ Synchronization completed successfully")
        else:
            print("✅ Dry run completed successfully")
    except KeyboardInterrupt:
        print("\n⚠️ Process interrupted by user")
        sys.exit(1)
    except Exception as e:
        print(f"❌ Unexpected error: {e}")
        sys.exit(1)

