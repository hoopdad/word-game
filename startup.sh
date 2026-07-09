echo "Starting at $(date)"
mkdir -p word-game-harness
cp init-pattern.yml word-game-harness
cd word-game-harness
../../enterprise-copilot-fleet-controller/scripts/init.sh -c init-pattern.yml | tee -a ../output.txt
gh api   -H "Accept: application/vnd.github.raw"   repos/hoopdad/mcaps-infra-skills/contents/scripts/install-skills.sh?ref=main   | bash -s -- --skill hub
echo "Ending at $(date)"

