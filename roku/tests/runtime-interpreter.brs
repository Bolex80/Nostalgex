' Which runtime the tests run in: this file goes into the off-device run
' (tests/run.sh), tests/runtime-device.brs into the TV's (deploy.sh --test).
function NxTestRuntime() as String
    return "interpreter"
end function
