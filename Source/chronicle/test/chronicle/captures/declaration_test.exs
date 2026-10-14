# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Captures.DeclarationTest do
  use ExUnit.Case, async: true

  alias Chronicle.Captures.Declaration

  # Golden fixtures mirror the kernel's own compiler specs, so the rendered text is proven to
  # compile against the real CDL grammar (Chronicle Source/Kernel/Core.Specs/Captures/Engine/
  # DeclarationLanguage/for_LanguageService/when_compiling).

  test "a simple api capture" do
    assert Declaration.render(%{
             name: "Customers",
             source: {:api, "CustomersApi", poll: "5m"},
             key: "customerId",
             map: nil,
             appends: [{"CustomerChanged", {:property, "email"}, [{"email", "$.email"}]}],
             nested: [],
             children: []
           }) == """
           capture Customers
             source api
               api CustomersApi
               poll 5m
             key customerId
             append CustomerChanged
               when email
               email = $.email
           """
  end

  test "an events capture" do
    assert Declaration.render(%{
             name: "ShipmentTracking",
             source: {:events, ["ShipmentDispatched", "ShipmentDelivered"]},
             key: "$eventSourceId",
             map: nil,
             appends: [
               {"OrderShipped", {:transition, "status", "pending", "dispatched"},
                [{"orderId", "$.orderId"}, {"shippedBy", "$context.correlationId"}]}
             ],
             nested: [],
             children: []
           }) == """
           capture ShipmentTracking
             source events
               from ShipmentDispatched
               from ShipmentDelivered
             key $eventSourceId
             append OrderShipped
               when status from "pending" to "dispatched"
               orderId = $.orderId
               shippedBy = $context.correlationId
           """
  end

  test "a capture with a map block" do
    assert Declaration.render(%{
             name: "Customers",
             source: {:api, "CustomersApi", poll: "5m"},
             key: "customerId",
             map: [
               {:rename, "fullName", "fornavn"},
               {:template, "displayName", "${fornavn} ${etternavn}"}
             ],
             appends: [
               {"CustomerChanged", {:any, ["firstName", "lastName"]},
                [{"firstName", "$.firstName"}]}
             ],
             nested: [],
             children: []
           }) == """
           capture Customers
             source api
               api CustomersApi
               poll 5m
             key customerId
             map
               fullName = fornavn
               displayName = `${fornavn} ${etternavn}`
             append CustomerChanged
               when firstName or lastName
               firstName = $.firstName
           """
  end

  test "a capture with a translate operation" do
    assert Declaration.render(%{
             name: "Customers",
             source: {:api, "CustomersApi", poll: "5m"},
             key: "customerId",
             map: [
               {:translate, "status", "status", [{"aktiv", "active"}, {"inaktiv", "inactive"}]}
             ],
             appends: [{"CustomerChanged", {:property, "status"}, [{"status", "$.status"}]}],
             nested: [],
             children: []
           }) == """
           capture Customers
             source api
               api CustomersApi
               poll 5m
             key customerId
             map
               status = status translate
                 "aktiv" => "active"
                 "inaktiv" => "inactive"
             append CustomerChanged
               when status
               status = $.status
           """
  end

  test "a capture with a when transition" do
    assert Declaration.render(%{
             name: "Customers",
             source: {:api, "CustomersApi", poll: "5m"},
             key: "customerId",
             map: nil,
             appends: [
               {"CustomerActivated", {:transition, "status", "inactive", "active"},
                [{"status", "$.status"}]}
             ],
             nested: [],
             children: []
           }) == """
           capture Customers
             source api
               api CustomersApi
               poll 5m
             key customerId
             append CustomerActivated
               when status from "inactive" to "active"
               status = $.status
           """
  end

  test "a capture with a nested block" do
    assert Declaration.render(%{
             name: "Customers",
             source: {:webhook, "/customers", []},
             key: "customerId",
             map: nil,
             appends: [],
             nested: [
               {"billingAddress", [{:rename, "street", "fakturaAdresse.gate"}],
                [{"BillingAddressChanged", {:property, "street"}, [{"street", "$.street"}]}]}
             ],
             children: []
           }) == """
           capture Customers
             source webhook
               path /customers
             key customerId
             nested billingAddress
               map
                 street = fakturaAdresse.gate
               append BillingAddressChanged
                 when street
                 street = $.street
           """
  end

  test "a capture with a children block" do
    assert Declaration.render(%{
             name: "Orders",
             source: {:webhook, "/orders", []},
             key: "orderId",
             map: nil,
             appends: [],
             nested: [],
             children: [
               {"lineItems", "lineNumber", nil,
                [
                  {"ItemAdded", :added, [{"lineNumber", "$.lineNumber"}]},
                  {"ItemChanged", {:property, "quantity"}, [{"quantity", "$.quantity"}]},
                  {"ItemRemoved", :removed, [{"lineNumber", "$.lineNumber"}]}
                ]}
             ]
           }) == """
           capture Orders
             source webhook
               path /orders
             key orderId
             children lineItems identified by lineNumber
               append ItemAdded
                 when added
                 lineNumber = $.lineNumber
               append ItemChanged
                 when quantity
                 quantity = $.quantity
               append ItemRemoved
                 when removed
                 lineNumber = $.lineNumber
           """
  end

  describe "deterministic_id/1" do
    test "is stable for the same module" do
      assert Declaration.deterministic_id(__MODULE__) == Declaration.deterministic_id(__MODULE__)
    end

    test "differs between modules" do
      refute Declaration.deterministic_id(__MODULE__) ==
               Declaration.deterministic_id(Chronicle.Captures.Declaration)
    end

    test "renders a well-formed UUID" do
      assert Declaration.deterministic_id(__MODULE__) =~
               ~r/^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
    end
  end
end
