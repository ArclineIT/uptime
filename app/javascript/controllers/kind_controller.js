import { Controller } from "@hotwired/stimulus"

// Shows only the fields that apply to the selected kind. Each field group lists
// the kinds it belongs to in data-kinds.
export default class extends Controller {
  static targets = [ "select", "group" ]

  connect() {
    this.update()
  }

  update() {
    const kind = this.selectTarget.value
    this.groupTargets.forEach((group) => {
      const shown = group.dataset.kinds.split(" ").includes(kind)
      group.hidden = !shown
      group.querySelectorAll("input, select, textarea").forEach((field) => { field.disabled = !shown })
    })
  }
}
