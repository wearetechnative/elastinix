{ config, pkgs, lib, ... }:
let
    cfg = config.elastinix.programs.e2e-twenty;
in {
    options.elastinix.programs.e2e-twenty = {
        enable = lib.mkEnableOption "Twenty e2e testing";
        twenty_url = lib.mkOption {
            type = lib.types.str;
            description = "The twenty domainurl";
        };
        twenty_username = lib.mkOption {
            type = lib.types.str;
            description = "The twenty login username";
        };
        twenty_password = lib.mkOption {
            type = lib.types.str;
            description = "The twenty login password";
        };
    };

    config = lib.mkIf cfg.enable {
        healthchecks.http.twenty = {
            url = cfg.twenty_url;
        };

        environment.systemPackages = [
            pkgs.jetbrains.rust-rover
            pkgs.rustup
            pkgs.cargo-insta
            pkgs.python312Packages.playwright
            pkgs.playwright-test
            pkgs.chromium
            pkgs.cowsay
        ];

        nixpkgs.config.allowUnfree = true;

        environment.variables = {
            LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [ pkgs.libuuid ];
            PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
        };


        healthchecks.localCommands.twenty_Login = pkgs.writers.writePython3 "test" { } ''
import re
from playwright.sync_api import Page, expect, sync_playwright
import time


def login(page: Page):
    page.goto("${cfg.twenty_url}")

    # Expect a title "to contain" a substring.
    expect(page).to_have_title(re.compile("Twenty"))

    page.get_by_text("Continue with Email").click()

    page.get_by_placeholder("Email").fill("${cfg.twenty_username}")
    page.locator('[type="submit"]').click()
    page.get_by_placeholder("Password").fill("${cfg.twenty_password}")

    page.locator('[type="submit"]').click()

    time.sleep(5)


def item_with_relation(page: Page):
    page.get_by_text("People").click()
    page.get_by_text("New record").click()
    page.get_by_placeholder("F‌‌irst name").fill("Play")
    page.get_by_placeholder("L‌‌ast name").fill("Wright")
    page.get_by_text("Open").click()
    page.get_by_text("Companies").click()
    page.get_by_text("New record").click()
    page.get_by_placeholder("Name").fill("Playwright")
    page.get_by_text("Open").click()

    time.sleep(1)

    people_banner = page.get_by_role("banner").filter(has_text="People")
    people_banner.locator("button").click()
    page.get_by_placeholder("Search").fill("Play Wright")
    page.get_by_text("Play Wright", exact=True).first.click(force=True)

    page.wait_for_selector('text="Delete"', state='visible')

    page.get_by_text("Delete").dblclick(force=True)
    page.wait_for_selector('text="Delete Record"', state='visible')
    page.get_by_test_id("confirmation-modal-confirm-button").click()

    page.wait_for_selector('text="Delete Record"', state='visible')
    time.sleep(1)

    page.get_by_text("People").click()
    page.get_by_text("Play Wright").first.click(force=True)
    page.get_by_text("Open").click()

    time.sleep(1)

    page.get_by_text("Delete").click(force=True)
    page.wait_for_selector('text="Delete Record"', state='visible')
    page.get_by_test_id("confirmation-modal-confirm-button").click()


if __name__ == "__main__":
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True)
        context = browser.new_context()
        page = context.new_page()

        print("Running twenty login...")
        login(page)
        print("Login test completed successfully!")
        print("Creating data...")
        item_with_relation(page)
        print("Data creation completed successfully!")

        context.close()
        browser.close()
        '';
    };
}

