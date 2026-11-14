import XCTest

/// 1.3.2: 设置 › AI 大模型 lists the providers that were set up. Each keeps its
/// own key, address and models; one model is in use and can be switched
/// without retyping anything.
final class Release132UITests: XCTestCase {
    private var app: XCUIApplication!

    @MainActor private func launch(_ extra: [String] = []) {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["--ui-test"] + extra; app.launch()
        XCTAssertTrue(app.tabBars.buttons["设置"].waitForExistence(timeout: 10))
    }
    @MainActor private func openAIModels() {
        app.tabBars.buttons["设置"].tap()
        let link = app.buttons["apiSettingsLink"]
        XCTAssertTrue(link.waitForExistence(timeout: 5)); link.tap()
        XCTAssertTrue(app.buttons["addProviderButton"].waitForExistence(timeout: 5))
    }
    @MainActor private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor private func any(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
    @MainActor private func any(_ identifier: String, containing part: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", identifier, part)).firstMatch
    }
    @MainActor private func text(_ element: XCUIElement) -> String {
        element.label + " " + ((element.value as? String) ?? "")
    }
    /// Scrolls the frontmost list up until `element` can be tapped.
    @MainActor private func reveal(_ element: XCUIElement) {
        for _ in 0..<6 where !(element.exists && element.isHittable) { app.swipeUp() }
        XCTAssertTrue(element.exists && element.isHittable, "\(element) cannot be reached")
    }
    @MainActor private func type(_ value: String, into field: XCUIElement) {
        reveal(field); field.tap(); field.typeText(value)
        let done = app.buttons["完成"].firstMatch
        if done.exists, done.isHittable { done.tap() }
    }
    @MainActor private func back() { app.navigationBars.buttons.element(boundBy: 0).tap() }
    @MainActor private func addDeepSeek() {
        app.buttons["addProviderButton"].tap()
        let preset = app.buttons["preset-deepSeek"]
        XCTAssertTrue(preset.waitForExistence(timeout: 5)); preset.tap()
        let add = app.buttons["confirmAddProviderButton"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        XCTAssertFalse(add.isEnabled, "A key is needed first")
        type("sk-ui-test", into: app.secureTextFields["apiKeyField"])
        XCTAssertTrue(add.isEnabled)
    }

    @MainActor func testPageShowsTheModelInUseAndItsProvider() {
        launch(); openAIModels()
        let card = any("activeModelCard")
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(card.label.contains("ui-test-model") && card.label.contains("自定义 API"), card.label)
        let row = app.buttons["provider-custom"]
        XCTAssertTrue(text(row).contains("1 个模型") && text(row).contains("正在用"), text(row))
        XCTAssertFalse(any("missingKeyHint").exists)
        attach("1.3.2-ai-models")

        app.buttons["aiHelpButton"].tap()
        XCTAssertTrue(app.buttons["closeAIHelp"].waitForExistence(timeout: 5))
        attach("1.3.2-ai-help")
        app.buttons["closeAIHelp"].tap()

        app.buttons["switchModelButton"].tap()
        XCTAssertTrue(app.buttons["switch-custom-ui-test-model"].waitForExistence(timeout: 5))
        app.buttons["closeModelSwitcher"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
    }

    @MainActor func testPageInDarkAppearance() {
        launch(["--fixture-dark"]); openAIModels()
        XCTAssertTrue(any("activeModelCard").waitForExistence(timeout: 5))
        attach("1.3.2-ai-models-dark")
        app.buttons["addProviderButton"].tap()
        XCTAssertTrue(app.buttons["preset-claude"].waitForExistence(timeout: 5))
        attach("1.3.2-add-provider-dark")
    }

    @MainActor func testPresetsPutClaudeChatGPTAndDeepSeekFirst() {
        launch(); openAIModels()
        app.buttons["addProviderButton"].tap()
        let order = ["claude", "openAI", "deepSeek", "qwen", "doubao", "kimi", "zhipu", "minimax", "gemini"]
        let rows = order.map { app.buttons["preset-" + $0] }
        XCTAssertTrue(rows[0].waitForExistence(timeout: 5))
        for index in 1..<rows.count {
            XCTAssertTrue(rows[index].exists, order[index])
            XCTAssertLessThan(rows[index - 1].frame.minY, rows[index].frame.minY, order[index])
        }
        XCTAssertTrue(text(rows[2]).contains("推荐"), text(rows[2]))
        attach("1.3.2-add-provider")
    }

    @MainActor func testAddingAPresetKeepsTheWorkingSetupUntilSwitched() {
        launch(); openAIModels()
        addDeepSeek()
        attach("1.3.2-preset-setup")
        // The official address is filled in, and stays folded away until asked for.
        let address = app.textFields["apiURLField"]
        XCTAssertFalse(address.exists)
        let advanced = app.buttons["disclosure-高级"]; reveal(advanced); advanced.tap()
        reveal(address)
        XCTAssertTrue((address.value as? String)?.contains("deepseek.com") == true, "\(String(describing: address.value))")
        reveal(app.buttons["apiStylePicker"])
        app.buttons["confirmAddProviderButton"].tap()
        XCTAssertTrue(any("settingsNotice", containing: "已添加 DeepSeek").waitForExistence(timeout: 8))
        let row = app.buttons["provider-deepSeek"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(text(row).contains("2 个模型"), text(row))
        let card = any("activeModelCard")
        XCTAssertTrue(card.label.contains("ui-test-model"), "Adding must not change a working setup: \(card.label)")
        attach("1.3.2-provider-added")

        app.buttons["switchModelButton"].tap()
        let choice = app.buttons["switch-deepSeek-deepseek-v4-pro"]
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        attach("1.3.2-switch-model")
        choice.tap()
        XCTAssertTrue(any("settingsNotice", containing: "deepseek-v4-pro").waitForExistence(timeout: 8))
        XCTAssertTrue(any("activeModelCard", containing: "deepseek-v4-pro").waitForExistence(timeout: 5))
        back()
        let link = app.buttons["apiSettingsLink"]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        XCTAssertTrue(text(link).contains("DeepSeek"), text(link))
    }

    @MainActor func testAddingACustomServiceWithAFetchedModel() {
        launch(); openAIModels()
        app.buttons["addProviderButton"].tap()
        let mode = app.segmentedControls["addProviderMode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 5)); mode.buttons["自定义"].tap()
        let add = app.buttons["confirmAddProviderButton"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        XCTAssertFalse(add.isEnabled)
        type("Test Lab", into: app.textFields["providerNameField"])
        type("https://fixture.invalid/v1", into: app.textFields["apiURLField"])
        type("ui-test-key", into: app.secureTextFields["apiKeyField"])
        let fetch = app.buttons["fetchModelsButton"]; reveal(fetch); fetch.tap()
        XCTAssertTrue(app.navigationBars["选择模型"].waitForExistence(timeout: 8))
        app.buttons["model-ui-test-model"].tap()
        let model = app.textFields["modelField"]
        XCTAssertTrue(model.waitForExistence(timeout: 5))
        XCTAssertEqual(model.value as? String, "ui-test-model")
        let test = app.buttons["testConnectionButton"]; reveal(test); test.tap()
        XCTAssertTrue(any("settingsNotice", containing: "连接正常").waitForExistence(timeout: 10))
        attach("1.3.2-custom-setup")
        XCTAssertTrue(add.isEnabled); add.tap()
        XCTAssertTrue(any("settingsNotice", containing: "已添加 Test Lab").waitForExistence(timeout: 8))
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'provider-custom-'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(text(row).contains("Test Lab") && text(row).contains("1 个模型"), text(row))
        XCTAssertTrue(any("activeModelCard").label.contains("自定义 API"), "The earlier service stays in use")
    }

    @MainActor func testModelsCanBeAddedTestedPutInUseAndDeleted() {
        launch(); openAIModels()
        app.buttons["provider-custom"].tap()
        let addModel = app.buttons["addModelButton"]
        XCTAssertTrue(addModel.waitForExistence(timeout: 5))
        attach("1.3.2-provider-page")
        addModel.tap()
        type("second-model", into: app.textFields["modelField"])
        attach("1.3.2-add-model")
        app.buttons["addTypedModelButton"].tap()
        XCTAssertTrue(any("settingsNotice", containing: "已添加 second-model").waitForExistence(timeout: 8))
        let second = app.buttons["model-second-model"]
        XCTAssertTrue(second.waitForExistence(timeout: 5)); second.tap()

        let use = app.buttons["setActiveModelButton"]
        XCTAssertTrue(app.buttons["apiStylePicker"].waitForExistence(timeout: 5))
        let reasoning = app.buttons["reasoningPicker"], advanced = app.buttons["disclosure-高级"]
        XCTAssertTrue(reasoning.exists)
        advanced.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: reasoning)
        waitForExpectations(timeout: 3)
        advanced.tap()
        XCTAssertTrue(reasoning.waitForExistence(timeout: 3))
        XCTAssertTrue(any("connectionResult", containing: "还没有测试过").exists)
        let test = app.buttons["testConnectionButton"]; reveal(test); test.tap()
        XCTAssertTrue(any("connectionResult", containing: "连接正常").waitForExistence(timeout: 10))
        attach("1.3.2-model-page")
        reveal(use)
        XCTAssertTrue(use.isEnabled); use.tap()
        expectation(for: NSPredicate(format: "label CONTAINS '正在使用' AND enabled == false"), evaluatedWith: use)
        waitForExpectations(timeout: 5)
        let delete = app.buttons["deleteModelButton"]
        reveal(delete)
        XCTAssertFalse(delete.isEnabled, "The model in use cannot be deleted")
        attach("1.3.2-model-in-use")

        back()
        let first = app.buttons["model-ui-test-model"]
        XCTAssertTrue(first.waitForExistence(timeout: 5)); first.tap()
        XCTAssertTrue(app.buttons["apiStylePicker"].waitForExistence(timeout: 5))
        reveal(delete)
        XCTAssertTrue(delete.isEnabled); delete.tap()
        let confirm = app.buttons["删除"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        XCTAssertFalse(first.exists, "The deleted model leaves the provider's list")
    }

    @MainActor func testAFailedConnectionTestShowsTheReason() {
        launch(["--fixture-error"]); openAIModels()
        app.buttons["provider-custom"].tap()
        let model = app.buttons["model-ui-test-model"]
        XCTAssertTrue(model.waitForExistence(timeout: 5)); model.tap()
        let test = app.buttons["testConnectionButton"]
        XCTAssertTrue(test.waitForExistence(timeout: 5)); reveal(test); test.tap()
        XCTAssertTrue(any("connectionResult", containing: "401").waitForExistence(timeout: 10))
        attach("1.3.2-connection-failed")
    }

    @MainActor func testKeyAndAddressEditsApplyOnlyAfterSave() {
        launch(); openAIModels()
        app.buttons["provider-custom"].tap()
        let edit = app.buttons["editCredentialsButton"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        XCTAssertTrue(text(edit).contains("已填写"), text(edit))
        let address = app.buttons["editAddressButton"]
        XCTAssertTrue(text(address).contains("fixture.invalid"), text(address))
        edit.tap()
        let save = app.buttons["saveCredentialsButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled, "Nothing changed yet")
        attach("1.3.2-credentials")

        type("x", into: app.secureTextFields["apiKeyField"])
        XCTAssertTrue(save.isEnabled)
        app.buttons["cancelCredentialsButton"].tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 5)); edit.tap()
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled, "A cancelled key edit must not come back")

        type("Test Lab", into: app.textFields["providerNameField"])
        XCTAssertTrue(save.isEnabled); save.tap()
        XCTAssertTrue(any("settingsNotice", containing: "已保存").waitForExistence(timeout: 8))
        XCTAssertTrue(app.navigationBars["Test Lab"].waitForExistence(timeout: 5))
        back(); back()
        let link = app.buttons["apiSettingsLink"]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        XCTAssertTrue(text(link).contains("Test Lab"), text(link))
    }

    @MainActor func testOnlyAProviderThatIsNotInUseCanBeDeleted() {
        launch(); openAIModels()
        addDeepSeek()
        app.buttons["confirmAddProviderButton"].tap()
        let row = app.buttons["provider-deepSeek"]
        XCTAssertTrue(row.waitForExistence(timeout: 8))

        app.buttons["provider-custom"].tap()
        let delete = app.buttons["deleteProviderButton"]
        XCTAssertTrue(app.buttons["addModelButton"].waitForExistence(timeout: 5))
        reveal(delete)
        XCTAssertFalse(delete.isEnabled, "The provider in use cannot be deleted")
        back()

        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        XCTAssertTrue(app.buttons["addModelButton"].waitForExistence(timeout: 5))
        attach("1.3.2-preset-provider-page")
        reveal(delete)
        XCTAssertTrue(delete.isEnabled); delete.tap()
        let confirm = app.buttons["删除"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        attach("1.3.2-delete-provider")
        confirm.tap()
        XCTAssertTrue(app.buttons["addProviderButton"].waitForExistence(timeout: 5))
        XCTAssertFalse(row.exists)
        XCTAssertTrue(any("activeModelCard").label.contains("ui-test-model"))
    }

    @MainActor func testFirstRunSetsUpTheDefaultProviderFromTheAddPage() {
        launch(["--fixture-defaults"]); openAIModels()
        let card = any("activeModelCard")
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(card.label.contains("deepseek-flash") && card.label.contains("DeepSeek"), card.label)
        XCTAssertTrue(any("missingKeyHint").exists)
        let row = app.buttons["provider-deepSeek"]
        XCTAssertTrue(text(row).contains("未填密钥"), text(row))
        attach("1.3.2-first-run")

        addDeepSeek()
        app.buttons["confirmAddProviderButton"].tap()
        XCTAssertTrue(any("settingsNotice", containing: "现在用它翻译").waitForExistence(timeout: 8))
        XCTAssertFalse(any("missingKeyHint").exists)
        XCTAssertFalse(text(row).contains("未填密钥"), text(row))
        XCTAssertTrue(text(row).contains("正在用"), text(row))
    }
}
