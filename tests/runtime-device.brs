' Which runtime the tests run in: this file goes into the TV's run
' (deploy.sh --test), tests/runtime-interpreter.brs into the off-device one.
function NxTestRuntime() as String
    return "device"
end function
