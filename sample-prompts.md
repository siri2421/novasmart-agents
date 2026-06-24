# Sample Prompts for Testing Price Match Agent

Use the following sample prompts to test your deployed Price Match Agent (either via the storefront web portal co-pilot, the Vertex AI Agent Platform Chat playground, or direct REST API curl requests).

---

### Scenario 1: Direct Approval (Discount <= 10%)
*   **Prompt:**
    ```text
    verify competitor price match for Barista Pro Espresso Machine SKU-HSE-4455 original price 450 requested price 427.50
    ```
*   **Expected Behavior:**
    The agent queries the BigQuery competitor pricing table, finds that a competitor (like `AlphaStore`) is selling the item for `$427.50`, and approves the match automatically since the discount is exactly 5% (which is below the 10% frontline approval threshold).

---

### Scenario 2: Escalation to Manager (10% < Discount <= 20%)
*   **Prompt:**
    ```text
    verify competitor price match for AeroPure Smart Air Purifier SKU-HSE-3322 original price 300 requested price 255
    ```
*   **Expected Behavior:**
    The agent verifies that a competitor is indeed selling the purifier for `$255` (a 15% discount). Because 15% is higher than the 10% direct frontline approval limit but within the 20% escalation threshold, the agent will direct the user to escalate the request to a pricing manager for approval.

---

### Scenario 3: Request Rejected (Discount > 20%)
*   **Prompt:**
    ```text
    verify competitor price match for SoundWave Pro Studio Monitors SKU-HSE-5566 original price 800 requested price 550
    ```
*   **Expected Behavior:**
    The agent checks competitor listings and sees that the requested price is `$550` (a 31% discount). Because the discount exceeds the maximum 20% discount policy, the agent will immediately reject the match request.
