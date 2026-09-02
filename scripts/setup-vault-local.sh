#!/bin/bash
# setup-vault-local.sh - One-command vault setup for local development
# 
# Usage:
#   bash scripts/setup-vault-local.sh
#
# This script:
# 1. Creates a vault password file (~/.vault_pass)
# 2. Encrypts vault.yml with the password
# 3. Verifies encryption
# 4. Shows you how to use it with AWX

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

VAULT_FILE="../ansible-lab/inventory/group_vars/github_runners/vault.yml"
VAULT_PASS_FILE="$HOME/.vault_pass"
VAULT_PASS_TEMP=".vault_pass_temp_setup"

echo -e "${GREEN}=== Ansible Vault Setup for GitHub Runner ===${NC}"
echo

# Step 1: Check if vault.yml exists
if [ ! -f "$VAULT_FILE" ]; then
    echo -e "${RED}✗ Vault file not found: $VAULT_FILE${NC}"
    exit 1
fi

# Step 2: Check if vault.yml is already encrypted
if file "$VAULT_FILE" | grep -q "data"; then
    echo -e "${GREEN}✓ Vault file appears to be encrypted${NC}"
else
    echo -e "${YELLOW}⚠ Vault file appears to be plain-text${NC}"
    read -p "Do you want to encrypt it now? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        ENCRYPT_NEEDED=1
    fi
fi

# Step 3: Create or use existing vault password file
if [ ! -f "$VAULT_PASS_FILE" ]; then
    echo -e "${YELLOW}Creating vault password file...${NC}"
    read -sp "Enter vault password (minimum 4 characters): " VAULT_PASS
    echo
    
    # Check length: allow 4 or more characters/digits
    if [ ${#VAULT_PASS} -lt 4 ]; then
        echo -e "${RED}✗ Password must be at least 4 characters long${NC}"
        exit 1
    fi
    
    read -sp "Confirm password: " VAULT_PASS_CONFIRM
    echo
    
    if [ "$VAULT_PASS" != "$VAULT_PASS_CONFIRM" ]; then
        echo -e "${RED}✗ Passwords do not match${NC}"
        exit 1
    fi
    
    # Write to temporary file first
    echo "$VAULT_PASS" > "$VAULT_PASS_TEMP"
    chmod 600 "$VAULT_PASS_TEMP"
    
    # Test encryption with temp file
    if ansible-vault encrypt --vault-password-file="$VAULT_PASS_TEMP" "$VAULT_FILE" 2>/dev/null; then
        echo -e "${GREEN}✓ Encryption successful${NC}"
        
        # Move temp to final location
        mv "$VAULT_PASS_TEMP" "$VAULT_PASS_FILE"
        chmod 600 "$VAULT_PASS_FILE"
        echo -e "${GREEN}✓ Vault password saved: $VAULT_PASS_FILE${NC}"
    else
        rm -f "$VAULT_PASS_TEMP"
        echo -e "${RED}✗ Encryption failed${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✓ Vault password file already exists: $VAULT_PASS_FILE${NC}"
    
    if [ "$ENCRYPT_NEEDED" = "1" ]; then
        echo "Encrypting vault.yml..."
        ansible-vault encrypt --vault-password-file="$VAULT_PASS_FILE" "$VAULT_FILE"
        echo -e "${GREEN}✓ Encryption complete${NC}"
    fi
fi

# Step 4: Verify encryption
echo
echo -e "${YELLOW}Verifying encryption...${NC}"
if ansible-vault view --vault-password-file="$VAULT_PASS_FILE" "$VAULT_FILE" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Vault decryption successful${NC}"
else
    echo -e "${RED}✗ Vault decryption failed${NC}"
    exit 1
fi

# Step 5: Check .gitignore
echo
echo -e "${YELLOW}Checking .gitignore...${NC}"
if grep -q ".vault_pass" .gitignore 2>/dev/null; then
    echo -e "${GREEN}✓ .vault_pass is in .gitignore${NC}"
else
    echo -e "${YELLOW}⚠ .vault_pass NOT in .gitignore. Adding it...${NC}"
    echo ".vault_pass" >> .gitignore
    echo ".vault_pass.*" >> .gitignore
    echo -e "${GREEN}✓ Added to .gitignore${NC}"
fi

# Step 6: Display vault content (for copying to AWX)
echo
echo -e "${GREEN}=== SUCCESS ===${NC}"
echo
echo -e "${YELLOW}Next steps:${NC}"
echo "1. View vault content (for AWX setup):"
echo -e "   ${GREEN}cat $VAULT_PASS_FILE${NC}"
echo
echo "2. Test playbook locally:"
echo -e "   ${GREEN}ansible-playbook playbooks/provision-github-runner.yaml \\${NC}"
echo -e "   ${GREEN}  -i inventory/hosts \\${NC}"
echo -e "   ${GREEN}  --vault-password-file=$VAULT_PASS_FILE \\${NC}"
echo -e "   ${GREEN}  --check${NC}"
echo
echo "3. Commit encrypted vault to GitHub:"
echo -e "   ${GREEN}git add inventory/group_vars/github_runners/vault.yml${NC}"
echo -e "   ${GREEN}git commit -m 'Add encrypted vault'${NC}"
echo -e "   ${GREEN}git push origin main${NC}"
echo
echo "4. Set up AWX Vault Credential:"
echo -e "   ${YELLOW}a. AWX Web UI > Credentials > Create Credential${NC}"
echo -e "   ${YELLOW}b. Credential Type: Vault${NC}"
echo -e "   ${YELLOW}c. Name: github-runner-vault-password${NC}"
echo -e "   ${YELLOW}d. Vault Password: (paste content of $VAULT_PASS_FILE)${NC}"
echo -e "   ${YELLOW}e. Save${NC}"
echo
echo "5. Add Vault Credential to Job Template:"
echo -e "   ${YELLOW}a. Templates > Create Job Template${NC}"
echo -e "   ${YELLOW}b. Credentials > Add > Select 'github-runner-vault-password'${NC}"
echo -e "   ${YELLOW}c. Vault Credential: github-runner-vault-password${NC}"
echo -e "   ${YELLOW}d. Save and Launch${NC}"
echo
echo -e "${GREEN}✓ Vault setup complete!${NC}"
