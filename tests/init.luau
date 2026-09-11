local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Jest = require(ReplicatedStorage.DevPackages.Jest)

return function()
    local status, result = Jest.runCLI(script, { verbose = true, ci = false }, { script }):awaitStatus()
    if status ~= "Resolved" then
        error(`[tests] Jest failed to run: {result}`)
    end

    local results = result.results
    script:SetAttribute("Passed", results.numPassedTests)
    script:SetAttribute("Failed", results.numFailedTests)
    script:SetAttribute("FailedSuites", results.numFailedTestSuites)
    script:SetAttribute("Finished", true)
    assert(results.numFailedTests == 0 and results.numFailedTestSuites == 0, "[tests] Test failures")
    assert(results.numPassedTests > 0, "[tests] No tests found")
    print(`[tests] {results.numPassedTests} tests passed`)
    return results
end
